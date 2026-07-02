import 'dart:async';
import 'dart:convert';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'anthropic_defaults.dart';

/// A [ChatClient] implementation backed by Anthropic's Messages API.
final class AnthropicChatClient implements ChatClient {
  /// Creates an Anthropic chat client adapter.
  AnthropicChatClient(
    this.client, {
    this.modelId,
    int? defaultMaxTokens,
    List<String> betas = const [],
  }) : defaultMaxTokens =
           defaultMaxTokens ?? AnthropicDefaults.defaultMaxTokens,
       betas = List.unmodifiable(betas);

  /// The underlying Anthropic client.
  final anthropic.AnthropicClient client;

  /// Default model used when [ChatOptions.modelId] is not provided.
  final String? modelId;

  /// Default maximum output tokens used when [ChatOptions.maxOutputTokens] is
  /// not provided.
  final int defaultMaxTokens;

  /// Anthropic beta headers to send with each request.
  final List<String> betas;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final abort = _AbortTrigger.fromToken(cancellationToken);
    try {
      final request = _buildRequest(messages, options, stream: false);
      final response = await client.messages.create(
        request,
        abortTrigger: abort?.future,
        betas: betas,
      );
      return _toChatResponse(response);
    } finally {
      abort?.dispose();
    }
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final abort = _AbortTrigger.fromToken(cancellationToken);
    try {
      final request = _buildRequest(messages, options, stream: true);
      final stream = client.messages.createStream(
        request,
        abortTrigger: abort?.future,
        betas: betas,
      );

      String? responseId;
      String? effectiveModelId;
      anthropic.Usage? startUsage;
      final toolUses = <int, _StreamingToolUse>{};
      final thinkingSignatures = <int, StringBuffer>{};

      await for (final event in stream) {
        cancellationToken?.throwIfCancellationRequested();

        switch (event) {
          case anthropic.MessageStartEvent(:final message):
            responseId = message.id;
            effectiveModelId = message.model;
            startUsage = message.usage;
          case anthropic.ContentBlockStartEvent(
            :final index,
            :final contentBlock,
          ):
            if (contentBlock is anthropic.ToolUseBlock) {
              toolUses[index] = _StreamingToolUse(contentBlock);
            } else if (contentBlock is anthropic.ThinkingBlock) {
              thinkingSignatures[index] = StringBuffer(
                contentBlock.signature,
              );
              if (contentBlock.thinking.isNotEmpty) {
                yield ChatResponseUpdate(
                  role: ChatRole.assistant,
                  contents: [TextReasoningContent(contentBlock.thinking)],
                  responseId: responseId,
                  modelId: effectiveModelId,
                  rawRepresentation: event,
                );
              }
            }
          case anthropic.ContentBlockDeltaEvent(:final delta):
            if (delta is anthropic.TextDelta && delta.text.isNotEmpty) {
              yield ChatResponseUpdate(
                role: ChatRole.assistant,
                contents: [TextContent(delta.text)],
                responseId: responseId,
                modelId: effectiveModelId,
                rawRepresentation: event,
              );
            } else if (delta is anthropic.InputJsonDelta) {
              toolUses[event.index]?.write(delta.partialJson);
            } else if (delta is anthropic.ThinkingDelta &&
                delta.thinking.isNotEmpty) {
              yield ChatResponseUpdate(
                role: ChatRole.assistant,
                contents: [TextReasoningContent(delta.thinking)],
                responseId: responseId,
                modelId: effectiveModelId,
                rawRepresentation: event,
              );
            } else if (delta is anthropic.SignatureDelta) {
              thinkingSignatures[event.index]?.write(delta.signature);
            }
          case anthropic.ContentBlockStopEvent(:final index):
            final toolUse = toolUses.remove(index);
            if (toolUse != null) {
              final block = toolUse.toBlock();
              yield ChatResponseUpdate(
                role: ChatRole.assistant,
                contents: [toolUse.toFunctionCall(block)],
                responseId: responseId,
                modelId: effectiveModelId,
                rawRepresentation: event,
              );
            }
            // Emit the accumulated signature as a zero-length reasoning
            // content; serialization joins it with the preceding thinking
            // text so the block can be echoed back verbatim.
            final signature = thinkingSignatures.remove(index);
            if (signature != null && signature.isNotEmpty) {
              yield ChatResponseUpdate(
                role: ChatRole.assistant,
                contents: [
                  TextReasoningContent(
                    '',
                    additionalProperties: {
                      'signature': signature.toString(),
                    },
                  ),
                ],
                responseId: responseId,
                modelId: effectiveModelId,
                rawRepresentation: event,
              );
            }
          case anthropic.MessageDeltaEvent(:final delta, :final usage):
            yield ChatResponseUpdate(
              role: ChatRole.assistant,
              responseId: responseId,
              modelId: effectiveModelId,
              finishReason: _mapStopReason(delta.stopReason),
              usage: _toDeltaUsageDetails(usage, startUsage),
              rawRepresentation: event,
              additionalProperties: _stopProperties(
                delta.stopDetails,
                delta.stopSequence,
              ),
            );
          case anthropic.ErrorEvent():
            throw StateError('Anthropic streaming error: ${event.toJson()}');
          default:
            break;
        }
      }
    } finally {
      abort?.dispose();
    }
  }

  @override
  T? getService<T>({Object? key}) {
    if (T == anthropic.AnthropicClient) return client as T;
    if (T == AnthropicChatClient) return this as T;
    return null;
  }

  @override
  void dispose() {
    // The underlying AnthropicClient is caller-owned.
  }

  anthropic.MessageCreateRequest _buildRequest(
    Iterable<ChatMessage> messages,
    ChatOptions? options, {
    required bool stream,
  }) {
    final effectiveModel = options?.modelId ?? modelId;
    if (effectiveModel == null || effectiveModel.trim().isEmpty) {
      throw ArgumentError.value(
        effectiveModel,
        'modelId',
        'An Anthropic model id must be provided.',
      );
    }

    final systemParts = <String>[];
    if (options?.instructions != null &&
        options!.instructions!.trim().isNotEmpty) {
      systemParts.add(options.instructions!);
    }

    final inputMessages = <anthropic.InputMessage>[];
    for (final message in messages) {
      if (message.role == ChatRole.system) {
        _ensureTextOnly(message);
        if (message.text.trim().isNotEmpty) {
          systemParts.add(message.text);
        }
        continue;
      }

      if (message.contents.isEmpty) continue;
      final inputMessage = _toAnthropicMessage(message);
      if (inputMessage != null) inputMessages.add(inputMessage);
    }

    return anthropic.MessageCreateRequest(
      model: effectiveModel,
      messages: inputMessages,
      maxTokens: options?.maxOutputTokens ?? defaultMaxTokens,
      system: systemParts.isEmpty
          ? null
          : anthropic.SystemPrompt.text(systemParts.join('\n\n')),
      stopSequences: options?.stopSequences,
      stream: stream,
      temperature: options?.temperature,
      topP: options?.topP,
      topK: options?.topK,
      tools: _toAnthropicTools(options?.tools),
      toolChoice: _toToolChoice(options),
    );
  }

  /// Converts one chat message to an Anthropic input message.
  ///
  /// Blocks are emitted in the order the API requires: thinking blocks
  /// open assistant messages and `tool_result` blocks open user messages.
  /// Empty text blocks are dropped; returns `null` when nothing remains
  /// (both cause API 400s).
  anthropic.InputMessage? _toAnthropicMessage(ChatMessage message) {
    final bodyBlocks = <anthropic.InputContentBlock>[];
    final toolUseBlocks = <anthropic.InputContentBlock>[];
    final toolResultBlocks = <anthropic.InputContentBlock>[];

    for (final content in message.contents) {
      switch (content) {
        case TextContent(:final text):
          if (text.trim().isNotEmpty) {
            bodyBlocks.add(anthropic.InputContentBlock.text(text));
          }
        case TextReasoningContent():
          // Handled below: contiguous runs collapse into thinking blocks.
          break;
        case DataContent() when content.hasTopLevelMediaType('image'):
          bodyBlocks.add(_toImageBlock(content));
        case FunctionCallContent(:final callId, :final name, :final arguments):
          toolUseBlocks.add(
            anthropic.InputContentBlock.toolUse(
              id: callId,
              name: name,
              input: _dynamicMap(arguments),
            ),
          );
        case FunctionResultContent(
          :final callId,
          :final result,
          :final exception,
        ):
          toolResultBlocks.add(
            anthropic.InputContentBlock.toolResultText(
              toolUseId: callId,
              text: _resultText(result, exception),
              isError: exception != null,
            ),
          );
        default:
          throw UnsupportedError(
            'AnthropicChatClient only supports TextContent, '
            'TextReasoningContent, image DataContent, '
            'FunctionCallContent, and FunctionResultContent inputs. '
            'Unsupported content: ${content.runtimeType}.',
          );
      }
    }

    if (toolUseBlocks.isNotEmpty && toolResultBlocks.isNotEmpty) {
      throw UnsupportedError(
        'Anthropic messages cannot mix function calls and function results.',
      );
    }

    if (toolResultBlocks.isNotEmpty || message.role == ChatRole.tool) {
      final blocks = [...toolResultBlocks, ...bodyBlocks];
      return blocks.isEmpty
          ? null
          : anthropic.InputMessage.userBlocks(blocks);
    }

    if (toolUseBlocks.isNotEmpty || message.role == ChatRole.assistant) {
      final blocks = [
        ..._thinkingBlocks(message.contents),
        ...bodyBlocks,
        ...toolUseBlocks,
      ];
      return blocks.isEmpty
          ? null
          : anthropic.InputMessage.assistantBlocks(blocks);
    }

    return bodyBlocks.isEmpty
        ? null
        : anthropic.InputMessage.userBlocks(bodyBlocks);
  }

  /// Collapses contiguous runs of [TextReasoningContent] into `thinking`
  /// input blocks so extended-thinking turns can be echoed back.
  ///
  /// A run without a signature is dropped: the API rejects unsigned
  /// thinking blocks, and losing the (display-only) reasoning is the
  /// correct degradation. Streaming produces the signature as a trailing
  /// zero-length reasoning content; non-streaming attaches it to the
  /// block's own `additionalProperties`.
  List<anthropic.InputContentBlock> _thinkingBlocks(
    List<AIContent> contents,
  ) {
    final blocks = <anthropic.InputContentBlock>[];
    final text = StringBuffer();
    String? signature;

    void flush() {
      if (signature != null && text.isNotEmpty) {
        blocks.add(
          anthropic.InputContentBlock.fromJson(<String, dynamic>{
            'type': 'thinking',
            'thinking': text.toString(),
            'signature': signature,
          }),
        );
      }
      text.clear();
      signature = null;
    }

    for (final content in contents) {
      if (content is TextReasoningContent) {
        text.write(content.text);
        final blockSignature = content.additionalProperties?['signature'];
        if (blockSignature is String && blockSignature.isNotEmpty) {
          signature = blockSignature;
        }
      } else {
        flush();
      }
    }
    flush();
    return blocks;
  }

  /// Converts image [DataContent] to a base64 or URL image block.
  anthropic.InputContentBlock _toImageBlock(DataContent content) {
    final data = content.data;
    if (data != null) {
      final mediaType = anthropic.ImageMediaType.values.firstWhere(
        (type) => type.value == content.mediaType,
        orElse: () => throw UnsupportedError(
          'Anthropic supports JPEG, PNG, GIF, and WebP images. '
          'Unsupported media type: ${content.mediaType}.',
        ),
      );
      return anthropic.InputContentBlock.image(
        anthropic.ImageSource.base64(
          data: base64Encode(data),
          mediaType: mediaType,
        ),
      );
    }
    final uri = content.uri;
    if (uri != null && !uri.startsWith('data:')) {
      return anthropic.InputContentBlock.image(
        anthropic.ImageSource.url(uri),
      );
    }
    throw UnsupportedError(
      'Anthropic image content requires bytes or a URL.',
    );
  }

  void _ensureTextOnly(ChatMessage message) {
    for (final content in message.contents) {
      if (content is! TextContent) {
        throw UnsupportedError(
          'Anthropic system messages only support TextContent. '
          'Unsupported content: ${content.runtimeType}.',
        );
      }
    }
  }

  List<anthropic.ToolDefinition>? _toAnthropicTools(List<AITool>? tools) {
    if (tools == null || tools.isEmpty) return null;

    final result = <anthropic.ToolDefinition>[];
    for (final tool in tools) {
      if (tool is HostedWebSearchTool) {
        result.add(anthropic.ToolDefinition.builtIn(anthropic.WebSearchTool()));
        continue;
      }

      if (tool is! AIFunctionDeclaration) {
        throw UnsupportedError(
          'AnthropicChatClient only supports AIFunctionDeclaration tools. '
          'Unsupported tool: ${tool.runtimeType}.',
        );
      }

      result.add(
        anthropic.ToolDefinition.custom(
          anthropic.Tool(
            name: tool.name,
            description: tool.description,
            inputSchema: anthropic.InputSchema.fromJson(
              tool.parametersSchema ?? const <String, dynamic>{},
            ),
          ),
        ),
      );
    }

    return result;
  }

  anthropic.ToolChoice? _toToolChoice(ChatOptions? options) {
    final mode = options?.toolMode;
    if (mode == null) return null;

    final disableParallelToolUse = options?.allowMultipleToolCalls == false;

    if (mode == ChatToolMode.none) {
      return anthropic.ToolChoice.none();
    }
    if (mode == ChatToolMode.auto) {
      return anthropic.ToolChoice.auto(
        disableParallelToolUse: disableParallelToolUse,
      );
    }
    if (mode is RequiredChatToolMode) {
      final requiredFunctionName = mode.requiredFunctionName;
      if (requiredFunctionName == null) {
        return anthropic.ToolChoice.any(
          disableParallelToolUse: disableParallelToolUse,
        );
      }

      return anthropic.ToolChoice.tool(
        requiredFunctionName,
        disableParallelToolUse: disableParallelToolUse,
      );
    }

    return null;
  }

  ChatResponse _toChatResponse(anthropic.Message response) {
    return ChatResponse(
      messages: [
        ChatMessage(
          role: ChatRole.assistant,
          contents: _toAIContents(response.content),
          rawRepresentation: response,
        ),
      ],
      responseId: response.id,
      modelId: response.model,
      finishReason: _mapStopReason(response.stopReason),
      usage: _toUsageDetails(response.usage),
      rawRepresentation: response,
      additionalProperties: _stopProperties(
        response.stopDetails,
        response.stopSequence,
      ),
    );
  }

  List<AIContent> _toAIContents(List<anthropic.ContentBlock> blocks) {
    final contents = <AIContent>[];

    for (final block in blocks) {
      switch (block) {
        case anthropic.TextBlock(:final text):
          contents.add(TextContent(text)..rawRepresentation = block);
        case anthropic.ToolUseBlock(:final id, :final name, :final input):
          contents.add(
            FunctionCallContent(
              callId: id,
              name: name,
              arguments: _objectMap(input),
            )..rawRepresentation = block,
          );
        case anthropic.ThinkingBlock(:final thinking, :final signature):
          contents.add(
            TextReasoningContent(
              thinking,
              rawRepresentation: block,
              additionalProperties: {'signature': signature},
            ),
          );
        default:
          break;
      }
    }

    return contents;
  }

  ChatFinishReason? _mapStopReason(anthropic.StopReason? stopReason) {
    return switch (stopReason) {
      null => null,
      anthropic.StopReason.endTurn => ChatFinishReason.stop,
      anthropic.StopReason.stopSequence => ChatFinishReason.stop,
      anthropic.StopReason.maxTokens => ChatFinishReason.length,
      anthropic.StopReason.toolUse => ChatFinishReason.toolCalls,
      anthropic.StopReason.refusal => ChatFinishReason.contentFilter,
      _ => ChatFinishReason(stopReason.value),
    };
  }

  UsageDetails _toUsageDetails(anthropic.Usage usage) {
    final cacheRead =
        usage.cacheReadInputTokens ??
        (usage.cacheRead == null
            ? null
            : usage.cacheRead!.ephemeral1hInputTokens +
                  usage.cacheRead!.ephemeral5mInputTokens);

    return UsageDetails(
      inputTokenCount: usage.inputTokens,
      outputTokenCount: usage.outputTokens,
      totalTokenCount: usage.inputTokens + usage.outputTokens,
      cachedInputTokenCount: cacheRead,
      reasoningTokenCount: usage.outputTokensDetails?.thinkingTokens,
      additionalProperties: {'anthropic_usage': usage.toJson()},
    );
  }

  /// Builds usage from a `message_delta` event, falling back to the
  /// `message_start` usage for input-side counts the delta omits.
  UsageDetails _toDeltaUsageDetails(
    anthropic.MessageDeltaUsage usage,
    anthropic.Usage? startUsage,
  ) {
    final inputTokens = usage.inputTokens ?? startUsage?.inputTokens;
    final cacheRead =
        usage.cacheReadInputTokens ?? startUsage?.cacheReadInputTokens;
    return UsageDetails(
      inputTokenCount: inputTokens,
      outputTokenCount: usage.outputTokens,
      totalTokenCount: inputTokens == null
          ? null
          : inputTokens + usage.outputTokens,
      cachedInputTokenCount: cacheRead,
      reasoningTokenCount: usage.outputTokensDetails?.thinkingTokens,
      additionalProperties: {'anthropic_usage': usage.toJson()},
    );
  }

  Map<String, Object?>? _stopProperties(
    anthropic.RefusalStopDetails? stopDetails,
    String? stopSequence,
  ) {
    if (stopDetails == null && stopSequence == null) return null;
    final properties = <String, Object?>{};
    if (stopDetails != null) {
      properties['anthropic_stop_details'] = stopDetails.toJson();
    }
    if (stopSequence != null) {
      properties['anthropic_stop_sequence'] = stopSequence;
    }
    return properties;
  }

  Map<String, dynamic> _dynamicMap(Map<String, Object?>? value) {
    if (value == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(value);
  }

  Map<String, Object?> _objectMap(Map<String, dynamic> value) {
    return Map<String, Object?>.from(value);
  }

  String _resultText(Object? result, Exception? exception) {
    if (exception != null) return exception.toString();
    if (result == null) return '';
    if (result is String) return result;

    try {
      return jsonEncode(result);
    } on Object {
      return result.toString();
    }
  }
}

final class _AbortTrigger {
  _AbortTrigger._(this.future, this._registration);

  final Future<void> future;
  final CancellationTokenRegistration _registration;

  static _AbortTrigger? fromToken(CancellationToken? token) {
    if (token == null || !token.canBeCanceled) return null;
    if (token.isCancellationRequested) {
      return _AbortTrigger._(
        Future<void>.value(),
        CancellationTokenRegistration(0, null),
      );
    }

    final completer = Completer<void>();
    final registration = token.register((_) {
      if (!completer.isCompleted) completer.complete();
    });
    return _AbortTrigger._(completer.future, registration);
  }

  void dispose() => _registration.dispose();
}

final class _StreamingToolUse {
  _StreamingToolUse(this.initialBlock);

  final anthropic.ToolUseBlock initialBlock;
  final StringBuffer _inputJson = StringBuffer();

  void write(String partialJson) {
    _inputJson.write(partialJson);
  }

  anthropic.ToolUseBlock toBlock() {
    return anthropic.ToolUseBlock(
      id: initialBlock.id,
      name: initialBlock.name,
      input: _arguments().$1,
      caller: initialBlock.caller,
    );
  }

  FunctionCallContent toFunctionCall(anthropic.ToolUseBlock block) {
    final (arguments, exception) = _arguments();
    return FunctionCallContent(
        callId: block.id,
        name: block.name,
        arguments: Map<String, Object?>.from(arguments),
      )
      ..exception = exception
      ..rawRepresentation = block;
  }

  (Map<String, dynamic>, Exception?) _arguments() {
    final rawJson = _inputJson.toString();
    if (rawJson.isEmpty) {
      return (Map<String, dynamic>.from(initialBlock.input), null);
    }

    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) return (decoded, null);
      if (decoded is Map) return (Map<String, dynamic>.from(decoded), null);
      return (
        Map<String, dynamic>.from(initialBlock.input),
        FormatException('Anthropic tool input must be a JSON object.', rawJson),
      );
    } on Exception catch (exception) {
      return (Map<String, dynamic>.from(initialBlock.input), exception);
    }
  }
}
