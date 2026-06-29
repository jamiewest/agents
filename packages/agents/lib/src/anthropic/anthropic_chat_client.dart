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

      await for (final event in stream) {
        cancellationToken?.throwIfCancellationRequested();

        switch (event) {
          case anthropic.MessageStartEvent(:final message):
            responseId = message.id;
            effectiveModelId = message.model;
          case anthropic.ContentBlockDeltaEvent(:final delta):
            if (delta is anthropic.TextDelta && delta.text.isNotEmpty) {
              yield ChatResponseUpdate(
                role: ChatRole.assistant,
                contents: [TextContent(delta.text)],
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
              usage: _toDeltaUsageDetails(usage),
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
      inputMessages.add(_toAnthropicMessage(message));
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

  anthropic.InputMessage _toAnthropicMessage(ChatMessage message) {
    final blocks = <anthropic.InputContentBlock>[];
    var hasFunctionCall = false;
    var hasFunctionResult = false;

    for (final content in message.contents) {
      switch (content) {
        case TextContent(:final text):
          blocks.add(anthropic.InputContentBlock.text(text));
        case FunctionCallContent(:final callId, :final name, :final arguments):
          hasFunctionCall = true;
          blocks.add(
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
          hasFunctionResult = true;
          blocks.add(
            anthropic.InputContentBlock.toolResultText(
              toolUseId: callId,
              text: _resultText(result, exception),
              isError: exception != null,
            ),
          );
        default:
          throw UnsupportedError(
            'AnthropicChatClient only supports TextContent, '
            'FunctionCallContent, and FunctionResultContent inputs. '
            'Unsupported content: ${content.runtimeType}.',
          );
      }
    }

    if (hasFunctionCall && hasFunctionResult) {
      throw UnsupportedError(
        'Anthropic messages cannot mix function calls and function results.',
      );
    }

    if (hasFunctionResult || message.role == ChatRole.tool) {
      return anthropic.InputMessage.userBlocks(blocks);
    }

    if (hasFunctionCall || message.role == ChatRole.assistant) {
      return anthropic.InputMessage.assistantBlocks(blocks);
    }

    return anthropic.InputMessage.userBlocks(blocks);
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

  UsageDetails _toDeltaUsageDetails(anthropic.MessageDeltaUsage usage) {
    return UsageDetails(
      inputTokenCount: usage.inputTokens,
      outputTokenCount: usage.outputTokens,
      totalTokenCount: usage.inputTokens == null
          ? null
          : usage.inputTokens! + usage.outputTokens,
      cachedInputTokenCount: usage.cacheReadInputTokens,
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
