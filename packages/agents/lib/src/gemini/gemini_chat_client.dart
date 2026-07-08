import 'dart:async';
import 'dart:convert';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:http/http.dart' as http;

import 'gemini_client.dart';

/// Key under which a Gemini function call's `thoughtSignature` is stashed in
/// [FunctionCallContent.additionalProperties] so it can be echoed back
/// verbatim in a later turn.
const _thoughtSignatureKey = 'gemini_thought_signature';

/// Placeholder documented by Google for `thoughtSignature` values on
/// function calls that were not produced by Gemini (e.g. constructed
/// manually or replayed from another provider), which skips signature
/// validation instead of rejecting the request.
const _skipThoughtSignatureValidator = 'skip_thought_signature_validator';

/// A [ChatClient] implementation backed by the Gemini API.
final class GeminiChatClient implements ChatClient {
  /// Creates a Gemini chat client adapter.
  GeminiChatClient(this.client, {this.modelId});

  /// The underlying Gemini REST client.
  final GeminiClient client;

  /// Default model used when [ChatOptions.modelId] is not provided.
  final String? modelId;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final abort = _AbortTrigger.fromToken(cancellationToken);
    try {
      final effectiveModel = _effectiveModel(options);
      final body = _buildRequest(messages, options);
      final responseBody = await _postJson(
        effectiveModel,
        'generateContent',
        body,
        abortTrigger: abort?.future,
      );
      return _toChatResponse(responseBody, effectiveModel);
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
      final effectiveModel = _effectiveModel(options);
      final body = _buildRequest(messages, options);
      final accumulator = _GeminiStreamingAccumulator(this, effectiveModel);
      await for (final chunk in _postJsonStream(
        effectiveModel,
        body,
        abortTrigger: abort?.future,
      )) {
        cancellationToken?.throwIfCancellationRequested();
        for (final update in accumulator.add(chunk)) {
          yield update;
        }
      }
      yield* accumulator.finish();
    } finally {
      abort?.dispose();
    }
  }

  @override
  T? getService<T>({Object? key}) {
    if (T == GeminiClient) return client as T;
    if (T == GeminiChatClient) return this as T;
    return null;
  }

  @override
  void dispose() {
    // The underlying GeminiClient is caller-owned.
  }

  String _effectiveModel(ChatOptions? options) {
    final effectiveModel = options?.modelId ?? modelId;
    if (effectiveModel == null || effectiveModel.trim().isEmpty) {
      throw ArgumentError.value(
        effectiveModel,
        'modelId',
        'A Gemini model id must be provided.',
      );
    }
    return effectiveModel;
  }

  Map<String, Object?> _buildRequest(
    Iterable<ChatMessage> messages,
    ChatOptions? options,
  ) {
    final systemParts = <String>[];
    if (options?.instructions != null &&
        options!.instructions!.trim().isNotEmpty) {
      systemParts.add(options.instructions!);
    }

    final contents = <Map<String, Object?>>[];
    for (final message in messages) {
      if (message.role == ChatRole.system) {
        _ensureTextOnly(message);
        if (message.text.trim().isNotEmpty) {
          systemParts.add(message.text);
        }
        continue;
      }

      if (message.contents.isEmpty) continue;
      final content = _toGeminiContent(message);
      if (content != null) contents.add(content);
    }

    if (contents.isEmpty) {
      throw ArgumentError(
        'Gemini requires at least one non-system message; the API rejects '
        'an empty contents array.',
      );
    }

    final tools = options?.tools;
    return _withoutNulls({
      'contents': contents,
      'systemInstruction': systemParts.isEmpty
          ? null
          : {
              'parts': [
                {'text': systemParts.join('\n\n')},
              ],
            },
      'generationConfig': _generationConfig(options),
      'tools': _toGeminiTools(tools),
      'toolConfig': _toToolConfig(options, tools),
    });
  }

  /// Converts one chat message to a Gemini content object, or `null` when
  /// nothing serializable remains (the API rejects empty `parts`).
  Map<String, Object?>? _toGeminiContent(ChatMessage message) {
    final parts = <Map<String, Object?>>[];
    var hasFunctionCall = false;
    var hasFunctionResponse = false;

    for (final content in message.contents) {
      switch (content) {
        case TextContent(:final text, :final additionalProperties):
          final part = <String, Object?>{'text': text};
          final thoughtSignature = additionalProperties?[_thoughtSignatureKey];
          if (thoughtSignature is String) {
            part['thoughtSignature'] = thoughtSignature;
          }
          parts.add(part);
        case TextReasoningContent(:final text, :final additionalProperties):
          // Echo thought parts back in Gemini's own shape so multi-turn
          // thinking conversations replay cleanly.
          if (text.isEmpty) break;
          final part = <String, Object?>{'text': text, 'thought': true};
          final thoughtSignature = additionalProperties?[_thoughtSignatureKey];
          if (thoughtSignature is String) {
            part['thoughtSignature'] = thoughtSignature;
          }
          parts.add(part);
        case DataContent():
          parts.add(_toInlineDataPart(content));
        case UriContent(:final uri, :final mediaType):
          parts.add({
            'fileData': {'mimeType': mediaType, 'fileUri': uri.toString()},
          });
        case FunctionCallContent(
          :final name,
          :final arguments,
          :final additionalProperties,
        ):
          hasFunctionCall = true;
          final part = <String, Object?>{
            'functionCall': {'name': name, 'args': arguments ?? const {}},
          };
          final thoughtSignature = additionalProperties?[_thoughtSignatureKey];
          if (thoughtSignature is String) {
            part['thoughtSignature'] = thoughtSignature;
          } else if (!parts.any((part) => part['functionCall'] != null)) {
            // Gemini validates the first function call in the current step.
            // For calls not produced by Gemini, use Google's documented
            // placeholder to bypass signature validation.
            part['thoughtSignature'] = _skipThoughtSignatureValidator;
          }
          parts.add(part);
        case FunctionResultContent(
          :final callId,
          :final name,
          :final result,
          :final exception,
        ):
          hasFunctionResponse = true;
          parts.add({
            'functionResponse': {
              'name': name ?? callId,
              'response': _functionResponse(result, exception),
            },
          });
        default:
          throw UnsupportedError(
            'GeminiChatClient does not support ${content.runtimeType} inputs.',
          );
      }
    }

    if (hasFunctionCall && hasFunctionResponse) {
      throw UnsupportedError(
        'Gemini messages cannot mix function calls and function results.',
      );
    }

    if (parts.isEmpty) return null;

    return {
      'role': hasFunctionCall || message.role == ChatRole.assistant
          ? 'model'
          : 'user',
      'parts': parts,
    };
  }

  Map<String, Object?> _toInlineDataPart(DataContent content) {
    // DataContent.fromUri parses data: URIs (extensions >= 0.5.0), so any
    // data-URI-backed content arrives here with raw bytes populated.
    final data = content.data;
    if (data == null) {
      throw UnsupportedError(
        'Gemini DataContent must contain raw bytes or a base64 data URI.',
      );
    }

    final mediaType = content.mediaType;
    if (mediaType == null || mediaType.isEmpty) {
      throw UnsupportedError('Gemini inline data requires a media type.');
    }

    return {
      'inlineData': {'mimeType': mediaType, 'data': base64Encode(data)},
    };
  }

  void _ensureTextOnly(ChatMessage message) {
    for (final content in message.contents) {
      if (content is! TextContent) {
        throw UnsupportedError(
          'Gemini system messages only support TextContent. '
          'Unsupported content: ${content.runtimeType}.',
        );
      }
    }
  }

  Map<String, Object?>? _generationConfig(ChatOptions? options) {
    if (options == null) return null;

    final config = <String, Object?>{
      'temperature': options.temperature,
      'topP': options.topP,
      'topK': options.topK,
      'maxOutputTokens': options.maxOutputTokens,
      'stopSequences': options.stopSequences,
      'seed': options.seed,
      'frequencyPenalty': options.frequencyPenalty,
      'presencePenalty': options.presencePenalty,
    };

    switch (options.responseFormat) {
      case ChatResponseFormatJson():
        config['responseMimeType'] = 'application/json';
      case ChatResponseFormatJsonSchema(:final schema):
        config['responseMimeType'] = 'application/json';
        config['responseSchema'] = _stripAdditionalProperties(schema);
      default:
        break;
    }

    final cleaned = _withoutNulls(config);
    return cleaned.isEmpty ? null : cleaned;
  }

  List<Map<String, Object?>>? _toGeminiTools(List<AITool>? tools) {
    if (tools == null || tools.isEmpty) return null;

    final functionDeclarations = <Map<String, Object?>>[];
    final geminiTools = <Map<String, Object?>>[];

    for (final tool in tools) {
      if (tool is HostedWebSearchTool) {
        geminiTools.add({'googleSearch': <String, Object?>{}});
        continue;
      }

      if (tool is! AIFunctionDeclaration) {
        throw UnsupportedError(
          'GeminiChatClient only supports AIFunctionDeclaration tools. '
          'Unsupported tool: ${tool.runtimeType}.',
        );
      }

      functionDeclarations.add(
        _withoutNulls({
          'name': tool.name,
          'description': tool.description,
          'parameters': _stripAdditionalProperties(tool.parametersSchema),
        }),
      );
    }

    if (functionDeclarations.isNotEmpty) {
      geminiTools.insert(0, {'functionDeclarations': functionDeclarations});
    }

    return geminiTools;
  }

  Map<String, Object?>? _toToolConfig(
    ChatOptions? options,
    List<AITool>? tools,
  ) {
    final mode = options?.toolMode;
    final functionCallingConfig = <String, Object?>{};
    if (mode == ChatToolMode.none) {
      functionCallingConfig['mode'] = 'NONE';
    } else if (mode == ChatToolMode.auto) {
      functionCallingConfig['mode'] = 'AUTO';
    } else if (mode is RequiredChatToolMode) {
      functionCallingConfig['mode'] = 'ANY';
      final name = mode.requiredFunctionName;
      if (name != null) {
        functionCallingConfig['allowedFunctionNames'] = [name];
      }
    } else if (mode != null) {
      return null;
    }

    final toolConfig = _withoutNulls({
      'functionCallingConfig': functionCallingConfig.isEmpty
          ? null
          : functionCallingConfig,
      // Gemini requires this flag when combining function declarations with
      // built-in server-side tools (e.g. googleSearch) in the same request.
      'includeServerSideToolInvocations': _hasMixedTools(tools) ? true : null,
    });

    return toolConfig.isEmpty ? null : toolConfig;
  }

  bool _hasMixedTools(List<AITool>? tools) {
    if (tools == null || tools.isEmpty) return false;
    var hasFunctionDeclaration = false;
    var hasBuiltInTool = false;
    for (final tool in tools) {
      if (tool is HostedWebSearchTool) {
        hasBuiltInTool = true;
      } else if (tool is AIFunctionDeclaration) {
        hasFunctionDeclaration = true;
      }
    }
    return hasFunctionDeclaration && hasBuiltInTool;
  }

  ChatResponse _toChatResponse(
    Map<String, Object?> response,
    String requestedModel,
  ) {
    final candidate = _firstCandidate(response);
    final contents = candidate == null
        ? <AIContent>[]
        : _toAIContents(candidate);
    final usage = _usageDetails(response['usageMetadata']);

    // A prompt rejected by safety filters returns zero candidates with the
    // reason in promptFeedback; surface it instead of a silent empty
    // message with no finish reason.
    final finishReason = candidate == null && _blockReason(response) != null
        ? ChatFinishReason.contentFilter
        : _finishReason(candidate, contents);

    return ChatResponse(
      messages: [
        ChatMessage(
          role: ChatRole.assistant,
          contents: contents,
          rawRepresentation: candidate ?? response,
        ),
      ],
      responseId: response['responseId'] as String?,
      modelId: response['modelVersion'] as String? ?? requestedModel,
      finishReason: finishReason,
      usage: usage,
      rawRepresentation: response,
      additionalProperties: _responseProperties(response, candidate),
    );
  }

  /// The `promptFeedback.blockReason` value, when the prompt was blocked.
  static String? _blockReason(Map<String, Object?> response) {
    final feedback = response['promptFeedback'];
    if (feedback is! Map) return null;
    final reason = feedback['blockReason'];
    return reason is String && reason.isNotEmpty ? reason : null;
  }

  Map<String, Object?>? _firstCandidate(Map<String, Object?> response) {
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty) return null;
    final candidate = candidates.first;
    return candidate is Map ? Map<String, Object?>.from(candidate) : null;
  }

  List<AIContent> _toAIContents(Map<String, Object?> candidate) {
    final content = candidate['content'];
    if (content is! Map) return const [];
    final parts = content['parts'];
    if (parts is! List) return const [];

    final contents = <AIContent>[];
    for (final part in parts) {
      if (part is! Map) continue;
      final partMap = Map<String, Object?>.from(part);
      final text = partMap['text'];
      if (text is String) {
        final thoughtSignature = partMap['thoughtSignature'];
        if (text.isNotEmpty || thoughtSignature is String) {
          contents.add(_textPartContent(partMap, text, thoughtSignature));
        }
        continue;
      }

      final functionCall = partMap['functionCall'];
      if (functionCall is Map) {
        final callMap = Map<String, Object?>.from(functionCall);
        final name = callMap['name'];
        if (name is String) {
          final args = callMap['args'];
          final thoughtSignature = partMap['thoughtSignature'];
          contents.add(
            FunctionCallContent(
                callId: callMap['id'] as String? ?? name,
                name: name,
                arguments: args is Map ? Map<String, Object?>.from(args) : null,
              )
              ..rawRepresentation = partMap
              ..additionalProperties = thoughtSignature is String
                  ? {_thoughtSignatureKey: thoughtSignature}
                  : null,
          );
        }
      }
    }

    return contents;
  }

  /// Builds the content for a text part, honoring the `thought` flag so
  /// thought-summary parts surface as [TextReasoningContent] instead of
  /// polluting the prose.
  static AIContent _textPartContent(
    Map<String, Object?> partMap,
    String text,
    Object? thoughtSignature,
  ) {
    final properties = thoughtSignature is String
        ? {_thoughtSignatureKey: thoughtSignature}
        : null;
    if (partMap['thought'] == true) {
      return TextReasoningContent(
        text,
        rawRepresentation: partMap,
        additionalProperties: properties,
      );
    }
    return TextContent(text)
      ..rawRepresentation = partMap
      ..additionalProperties = properties;
  }

  ChatFinishReason? _finishReason(
    Map<String, Object?>? candidate,
    List<AIContent> contents,
  ) {
    if (contents.any((content) => content is FunctionCallContent)) {
      return ChatFinishReason.toolCalls;
    }

    final reason = candidate?['finishReason'];
    return switch (reason) {
      null => null,
      'STOP' => ChatFinishReason.stop,
      'MAX_TOKENS' => ChatFinishReason.length,
      'SAFETY' ||
      'RECITATION' ||
      'BLOCKLIST' ||
      'PROHIBITED_CONTENT' ||
      'SPII' ||
      'IMAGE_SAFETY' => ChatFinishReason.contentFilter,
      _ => ChatFinishReason(reason.toString()),
    };
  }

  UsageDetails? _usageDetails(Object? usage) {
    if (usage is! Map) return null;
    final map = Map<String, Object?>.from(usage);
    return UsageDetails(
      inputTokenCount: map['promptTokenCount'] as int?,
      outputTokenCount: map['candidatesTokenCount'] as int?,
      totalTokenCount: map['totalTokenCount'] as int?,
      cachedInputTokenCount: map['cachedContentTokenCount'] as int?,
      reasoningTokenCount: map['thoughtsTokenCount'] as int?,
      additionalProperties: {'gemini_usage': map},
    );
  }

  Map<String, Object?>? _responseProperties(
    Map<String, Object?> response,
    Map<String, Object?>? candidate,
  ) {
    final properties = <String, Object?>{};
    if (response['promptFeedback'] != null) {
      properties['gemini_prompt_feedback'] = response['promptFeedback'];
    }
    if (candidate?['safetyRatings'] != null) {
      properties['gemini_safety_ratings'] = candidate!['safetyRatings'];
    }
    if (candidate?['groundingMetadata'] != null) {
      properties['gemini_grounding_metadata'] = candidate!['groundingMetadata'];
    }

    return properties.isEmpty ? null : properties;
  }

  Map<String, Object?> _functionResponse(Object? result, Exception? exception) {
    if (exception != null) {
      return {'error': exception.toString()};
    }
    if (result == null) {
      return <String, Object?>{};
    }
    if (result is Map) {
      return Map<String, Object?>.from(result);
    }
    return {'result': result};
  }

  Future<Map<String, Object?>> _postJson(
    String modelId,
    String method,
    Map<String, Object?> body, {
    Future<void>? abortTrigger,
  }) async {
    final request = _request(
      client.endpoint(modelId, method),
      body,
      abortTrigger: abortTrigger,
    );
    final response = await client.httpClient.send(request);
    final responseBody = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwIfFailed(response, responseBody);
    }
    return jsonDecode(responseBody) as Map<String, Object?>;
  }

  Stream<Map<String, Object?>> _postJsonStream(
    String modelId,
    Map<String, Object?> body, {
    Future<void>? abortTrigger,
  }) async* {
    final request = _request(
      client.endpoint(
        modelId,
        'streamGenerateContent',
        queryParameters: {'alt': 'sse'},
      ),
      body,
      abortTrigger: abortTrigger,
    );
    final response = await client.httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final responseBody = await response.stream.bytesToString();
      _throwIfFailed(response, responseBody);
    }

    await for (final event in _sseEvents(response.stream)) {
      Object? decoded;
      try {
        decoded = jsonDecode(event);
      } on FormatException catch (error) {
        final snippet = event.length > 200
            ? '${event.substring(0, 200)}…'
            : event;
        throw FormatException(
          'Gemini streamed a malformed SSE JSON event '
          '(${error.message}): $snippet',
        );
      }
      yield decoded as Map<String, Object?>;
    }
  }

  http.AbortableRequest _request(
    Uri uri,
    Map<String, Object?> body, {
    Future<void>? abortTrigger,
  }) {
    return http.AbortableRequest('POST', uri, abortTrigger: abortTrigger)
      ..headers.addAll({
        'content-type': 'application/json',
        'x-goog-api-key': client.apiKey,
        ...client.defaultHeaders,
      })
      ..body = jsonEncode(body);
  }

  Stream<String> _sseEvents(Stream<List<int>> stream) async* {
    final data = <String>[];
    await for (final line
        in stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          yield data.join('\n');
          data.clear();
        }
        continue;
      }
      if (line.startsWith('data:')) {
        data.add(line.substring(5).trimLeft());
      }
    }

    if (data.isNotEmpty) {
      yield data.join('\n');
    }
  }

  Never _throwIfFailed(http.StreamedResponse response, String body) {
    throw http.ClientException(
      'Gemini API request failed with status ${response.statusCode}: $body',
      response.request?.url,
    );
  }

  Map<String, Object?> _withoutNulls(Map<String, Object?> value) {
    return Map.fromEntries(value.entries.where((entry) => entry.value != null));
  }

  /// Recursively strips `additionalProperties` from a JSON Schema-like
  /// structure. Gemini's schema format is a restricted OpenAPI subset that
  /// rejects unknown fields, so schemas carrying the standard JSON Schema
  /// `additionalProperties` keyword (as produced for other providers) must
  /// have it removed before being sent as `parameters` or `responseSchema`.
  Object? _stripAdditionalProperties(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (entry.key != 'additionalProperties')
            entry.key: _stripAdditionalProperties(entry.value),
      };
    }
    if (value is List) {
      return [for (final item in value) _stripAdditionalProperties(item)];
    }
    return value;
  }
}

final class _GeminiStreamingAccumulator {
  _GeminiStreamingAccumulator(this._client, this._requestedModel);

  final GeminiChatClient _client;
  final String _requestedModel;

  /// Pending calls in arrival order; [_openByIndex] tracks which pending a
  /// part index may still be appending fragments to.
  final List<_PendingFunctionCall> _functionCalls = [];
  final Map<int, _PendingFunctionCall> _openByIndex = {};

  List<ChatResponseUpdate> add(Map<String, Object?> response) {
    final candidate = _client._firstCandidate(response);
    if (candidate == null) {
      // A blocked prompt streams a single candidate-less chunk carrying
      // promptFeedback; surface it as a content-filter finish.
      if (GeminiChatClient._blockReason(response) != null) {
        return [
          ChatResponseUpdate(
            role: ChatRole.assistant,
            responseId: response['responseId'] as String?,
            modelId: response['modelVersion'] as String? ?? _requestedModel,
            finishReason: ChatFinishReason.contentFilter,
            usage: _client._usageDetails(response['usageMetadata']),
            rawRepresentation: response,
            additionalProperties: _client._responseProperties(response, null),
          ),
        ];
      }
      return const [];
    }

    final responseId = response['responseId'] as String?;
    final modelId = response['modelVersion'] as String? ?? _requestedModel;
    final updates = <ChatResponseUpdate>[];
    final nonFunctionContents = <AIContent>[];

    final content = candidate['content'];
    if (content is Map) {
      final parts = content['parts'];
      if (parts is List) {
        for (var i = 0; i < parts.length; i++) {
          final part = parts[i];
          if (part is! Map) continue;
          final partMap = Map<String, Object?>.from(part);
          final functionCall = partMap['functionCall'];
          if (functionCall is Map) {
            // Chunks are keyed by part index, but Gemini may (a) re-send
            // the same call finalized with its thoughtSignature, which
            // must merge, or (b) send a different parallel call at the
            // same index in the next chunk, which must NOT merge into the
            // previous one and corrupt both.
            final incoming = Map<String, Object?>.from(functionCall);
            var pending = _openByIndex[i];
            if (pending == null || !pending.acceptsMerge(incoming)) {
              pending = _PendingFunctionCall();
              _functionCalls.add(pending);
              _openByIndex[i] = pending;
            }
            pending.merge(partMap);
            continue;
          }

          final text = partMap['text'];
          final thoughtSignature = partMap['thoughtSignature'];
          if (text is String &&
              (text.isNotEmpty || thoughtSignature is String)) {
            nonFunctionContents.add(
              GeminiChatClient._textPartContent(
                partMap,
                text,
                thoughtSignature,
              ),
            );
          }
        }
      }
    }

    for (final content in nonFunctionContents) {
      updates.add(
        ChatResponseUpdate(
          role: ChatRole.assistant,
          contents: [content],
          responseId: responseId,
          modelId: modelId,
          rawRepresentation: candidate,
        ),
      );
    }

    final hasTerminalFields =
        candidate['finishReason'] != null || response['usageMetadata'] != null;
    if (!hasTerminalFields) return updates;

    final functionContents = _drainFunctionCalls();
    for (final content in functionContents) {
      updates.add(
        ChatResponseUpdate(
          role: ChatRole.assistant,
          contents: [content],
          responseId: responseId,
          modelId: modelId,
          rawRepresentation: content.rawRepresentation ?? candidate,
        ),
      );
    }

    final finishReason = _client._finishReason(
      candidate,
      functionContents.isNotEmpty ? functionContents : nonFunctionContents,
    );
    final usage = _client._usageDetails(response['usageMetadata']);
    if (finishReason != null || usage != null) {
      updates.add(
        ChatResponseUpdate(
          role: ChatRole.assistant,
          responseId: responseId,
          modelId: modelId,
          finishReason: finishReason,
          usage: usage,
          rawRepresentation: response,
          additionalProperties: _client._responseProperties(
            response,
            candidate,
          ),
        ),
      );
    }

    return updates;
  }

  Stream<ChatResponseUpdate> finish() async* {
    for (final content in _drainFunctionCalls()) {
      yield ChatResponseUpdate(
        role: ChatRole.assistant,
        contents: [content],
        modelId: _requestedModel,
        rawRepresentation: content.rawRepresentation,
      );
    }
  }

  List<AIContent> _drainFunctionCalls() {
    if (_functionCalls.isEmpty) return const [];
    final pending = List<_PendingFunctionCall>.of(_functionCalls);
    _functionCalls.clear();
    _openByIndex.clear();

    return [for (final call in pending) ?call.toContent()];
  }
}

final class _PendingFunctionCall {
  final Map<String, Object?> functionCall = {};
  final Map<String, Object?> rawPart = {};
  String? thoughtSignature;

  /// Whether [incoming] is a continuation/finalization of this pending
  /// call rather than a distinct parallel call.
  ///
  /// A nameless fragment always continues; a named part continues only
  /// when it matches this call's name and its args are absent, identical
  /// (a finalized re-send), or this call has none yet.
  bool acceptsMerge(Map<String, Object?> incoming) {
    final incomingName = incoming['name'];
    if (incomingName is! String) return true;
    final name = functionCall['name'];
    if (name is String && name != incomingName) return false;

    final incomingArgs = incoming['args'];
    final args = functionCall['args'];
    if (incomingArgs == null || args == null) return true;
    return jsonEncode(incomingArgs) == jsonEncode(args);
  }

  void merge(Map<String, Object?> partMap) {
    final incoming = partMap['functionCall'];
    if (incoming is Map) {
      functionCall.addAll(Map<String, Object?>.from(incoming));
    }

    final incomingSignature = partMap['thoughtSignature'];
    if (incomingSignature is String) {
      thoughtSignature = incomingSignature;
    }

    rawPart
      ..addAll(partMap)
      ..['functionCall'] = Map<String, Object?>.of(functionCall);
    if (thoughtSignature != null) {
      rawPart['thoughtSignature'] = thoughtSignature;
    } else {
      rawPart.remove('thoughtSignature');
    }
  }

  FunctionCallContent? toContent() {
    final name = functionCall['name'];
    if (name is! String) return null;
    final args = functionCall['args'];

    return FunctionCallContent(
        callId: functionCall['id'] as String? ?? name,
        name: name,
        arguments: args is Map ? Map<String, Object?>.from(args) : null,
      )
      ..rawRepresentation = Map<String, Object?>.of(rawPart)
      ..additionalProperties = thoughtSignature != null
          ? {_thoughtSignatureKey: thoughtSignature}
          : null;
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
