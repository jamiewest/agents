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
      await for (final chunk in _postJsonStream(
        effectiveModel,
        body,
        abortTrigger: abort?.future,
      )) {
        cancellationToken?.throwIfCancellationRequested();
        for (final update in _toStreamingUpdates(chunk, effectiveModel)) {
          yield update;
        }
      }
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
      contents.add(_toGeminiContent(message));
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

  Map<String, Object?> _toGeminiContent(ChatMessage message) {
    final parts = <Map<String, Object?>>[];
    var hasFunctionCall = false;
    var hasFunctionResponse = false;

    for (final content in message.contents) {
      switch (content) {
        case TextContent(:final text):
          parts.add({'text': text});
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
          parts.add({
            'functionCall': {'name': name, 'args': arguments ?? const {}},
            // Gemini 3 models reject function calls that are missing a
            // thought_signature. When replaying a call the model produced,
            // echo back the signature it returned; otherwise fall back to
            // Google's documented placeholder that skips signature
            // validation for calls not originated by Gemini.
            'thoughtSignature':
                additionalProperties?[_thoughtSignatureKey] as String? ??
                _skipThoughtSignatureValidator,
          });
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

    return {
      'role': hasFunctionCall || message.role == ChatRole.assistant
          ? 'model'
          : 'user',
      'parts': parts,
    };
  }

  Map<String, Object?> _toInlineDataPart(DataContent content) {
    if (content.data != null) {
      final mediaType = content.mediaType;
      if (mediaType == null || mediaType.isEmpty) {
        throw UnsupportedError('Gemini inline data requires a media type.');
      }
      return {
        'inlineData': {
          'mimeType': mediaType,
          'data': base64Encode(content.data!),
        },
      };
    }

    final uri = content.uri;
    if (uri != null && uri.startsWith('data:')) {
      final parsed = _parseDataUri(uri);
      return {
        'inlineData': {'mimeType': parsed.mediaType, 'data': parsed.base64Data},
      };
    }

    throw UnsupportedError(
      'Gemini DataContent must contain raw bytes or a base64 data URI.',
    );
  }

  _ParsedDataUri _parseDataUri(String uri) {
    final comma = uri.indexOf(',');
    if (comma <= 5) {
      throw UnsupportedError('Invalid data URI for Gemini inline data.');
    }

    final metadata = uri.substring(5, comma);
    final data = uri.substring(comma + 1);
    final parts = metadata.split(';');
    final mediaType = parts.first.isEmpty
        ? 'application/octet-stream'
        : parts.first;
    if (!parts.contains('base64')) {
      throw UnsupportedError('Gemini data URIs must be base64 encoded.');
    }

    return _ParsedDataUri(mediaType: mediaType, base64Data: data);
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
      'includeServerSideToolInvocations': _hasMixedTools(tools)
          ? true
          : null,
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
      finishReason: _finishReason(candidate, contents),
      usage: usage,
      rawRepresentation: response,
      additionalProperties: _responseProperties(response, candidate),
    );
  }

  List<ChatResponseUpdate> _toStreamingUpdates(
    Map<String, Object?> response,
    String requestedModel,
  ) {
    final candidate = _firstCandidate(response);
    if (candidate == null) return const [];

    final responseId = response['responseId'] as String?;
    final modelId = response['modelVersion'] as String? ?? requestedModel;
    final contents = _toAIContents(candidate);
    final updates = <ChatResponseUpdate>[];

    for (final content in contents) {
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

    final finishReason = _finishReason(candidate, contents);
    final usage = _usageDetails(response['usageMetadata']);
    if (finishReason != null || usage != null) {
      updates.add(
        ChatResponseUpdate(
          role: ChatRole.assistant,
          responseId: responseId,
          modelId: modelId,
          finishReason: finishReason,
          usage: usage,
          rawRepresentation: response,
          additionalProperties: _responseProperties(response, candidate),
        ),
      );
    }

    return updates;
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
      if (text is String && text.isNotEmpty) {
        contents.add(TextContent(text)..rawRepresentation = partMap);
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
      yield jsonDecode(event) as Map<String, Object?>;
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

final class _ParsedDataUri {
  const _ParsedDataUri({required this.mediaType, required this.base64Data});

  final String mediaType;
  final String base64Data;
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
