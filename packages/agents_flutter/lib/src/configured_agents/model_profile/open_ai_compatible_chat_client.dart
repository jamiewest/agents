// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'open_ai_model_profile.dart';
import 'tool_formats/hermes_tool_format.dart';
import 'tool_formats/think_tag_filter.dart';
import 'tool_formats/tool_format.dart';
import 'tool_formats/tool_format_registry.dart';

/// Hardens `OpenAIChatClient` for multi-model OpenAI-compatible endpoints
/// (Groq, local inference servers, proxies).
///
/// The wrapped client from `package:extensions` covers plain chat but
/// leaves tool calling and reasoning to the caller:
///
/// * it never sends `tools`/`tool_choice`/`parallel_tool_calls`;
/// * streamed `tool_calls` deltas and `reasoning` fields are dropped
///   (only `delta.content` is parsed);
/// * tool results are serialized with `toString()` (not JSON);
/// * assistant text is dropped from messages that also carry tool calls.
///
/// This decorator compensates through public seams only: request fields
/// ride in via `ChatOptions.rawRepresentationFactory`, and streamed
/// extras are recovered from each update's `rawRepresentation` chunk.
/// Per-model behavior comes from an [OpenAIModelProfile]: native tool
/// calling, a prompt-injected fallback using the model family's
/// [ToolFormat], and `<think>` reasoning-tag extraction.
final class OpenAICompatibleChatClient implements ChatClient {
  /// Wraps [inner] with the behavior described by [profile].
  ///
  /// [toolFormat] overrides the format resolved from
  /// [OpenAIModelProfile.fallbackFormatName] (Hermes when unknown).
  OpenAICompatibleChatClient(
    this._inner, {
    this.profile = const OpenAIModelProfile(),
    ToolFormat? toolFormat,
  }) : _toolFormat =
           toolFormat ??
           resolveToolFormat(profile.fallbackFormatName) ??
           const HermesToolFormat();

  final ChatClient _inner;

  /// The per-model behavior this client applies.
  final OpenAIModelProfile profile;

  final ToolFormat _toolFormat;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final injected = _usePromptInjection(options);
    final response = await _inner.getResponse(
      messages: injected
          ? _rewriteForInjection(messages)
          : _normalizeMessages(messages),
      options: injected ? _injectedOptions(options) : _nativeOptions(options),
      cancellationToken: cancellationToken,
    );
    return injected
        ? _parseInjectedResponse(response)
        : _recoverNativeExtras(response);
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) {
    final injected = _usePromptInjection(options);
    final stream = _inner.getStreamingResponse(
      messages: injected
          ? _rewriteForInjection(messages)
          : _normalizeMessages(messages),
      options: injected ? _injectedOptions(options) : _nativeOptions(options),
      cancellationToken: cancellationToken,
    );
    return injected
        ? _decodeInjectedStream(stream)
        : _decorateNativeStream(stream);
  }

  @override
  T? getService<T>({Object? key}) {
    if (T == OpenAICompatibleChatClient) return this as T;
    if (T == OpenAIModelProfile) return profile as T;
    return _inner.getService<T>(key: key);
  }

  @override
  void dispose() => _inner.dispose();

  // ---------------------------------------------------------------------
  // Mode selection
  // ---------------------------------------------------------------------

  List<AIFunctionDeclaration> _declaredTools(ChatOptions? options) =>
      options?.tools?.whereType<AIFunctionDeclaration>().toList() ??
      const <AIFunctionDeclaration>[];

  bool _usePromptInjection(ChatOptions? options) =>
      profile.toolMode == ToolCallingMode.promptInjected &&
      _declaredTools(options).isNotEmpty;

  bool get _stripThinkTags =>
      profile.reasoningTags == ReasoningTagStyle.thinkTags;

  // ---------------------------------------------------------------------
  // Native mode: request side
  // ---------------------------------------------------------------------

  /// Adds `tools`, `tool_choice`, and `parallel_tool_calls` to the
  /// request body through the raw-representation seam.
  ///
  /// A caller-supplied factory runs first and its keys win; a caller
  /// returning a non-map raw object is passed through untouched.
  ChatOptions? _nativeOptions(ChatOptions? options) {
    final tools = _declaredTools(options);
    if (profile.toolMode == ToolCallingMode.none || tools.isEmpty) {
      return options;
    }

    final result = (options ?? ChatOptions()).clone();
    final callerFactory = options?.rawRepresentationFactory;
    final toolMode = options?.toolMode;
    final allowParallel =
        options?.allowMultipleToolCalls ?? profile.parallelToolCalls;

    result.rawRepresentationFactory = (client) {
      final raw = callerFactory?.call(client);
      if (raw != null && raw is! Map<String, dynamic>) return raw;
      final map = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.of(raw as Map<String, dynamic>);
      map.putIfAbsent(
        'tools',
        () => [for (final tool in tools) _toolJson(tool)],
      );
      final choice = _toolChoiceJson(toolMode);
      if (choice != null) map.putIfAbsent('tool_choice', () => choice);
      if (!allowParallel) {
        map.putIfAbsent('parallel_tool_calls', () => false);
      }
      return map;
    };
    return result;
  }

  static Map<String, dynamic> _toolJson(AIFunctionDeclaration tool) => {
    'type': 'function',
    'function': {
      'name': tool.name,
      'description': tool.description ?? '',
      'parameters':
          tool.parametersSchema ?? const {'type': 'object', 'properties': {}},
    },
  };

  static Object? _toolChoiceJson(ChatToolMode? mode) => switch (mode) {
    NoneChatToolMode() => 'none',
    RequiredChatToolMode(requiredFunctionName: final name?) => {
      'type': 'function',
      'function': {'name': name},
    },
    RequiredChatToolMode() => 'required',
    AutoChatToolMode() => 'auto',
    _ => null,
  };

  // ---------------------------------------------------------------------
  // Message normalization (native and none modes)
  // ---------------------------------------------------------------------

  /// Reshapes history so the inner client serializes it faithfully:
  /// JSON-encodes structured tool results, splits assistant messages that
  /// carry both text and tool calls (the inner client drops the text),
  /// strips reasoning content, and drops empty messages.
  List<ChatMessage> _normalizeMessages(Iterable<ChatMessage> messages) {
    final out = <ChatMessage>[];
    for (final message in messages) {
      final contents = <AIContent>[];
      for (final content in message.contents) {
        if (content is TextReasoningContent) continue;
        if (content is FunctionResultContent &&
            content.result != null &&
            content.result is! String) {
          contents.add(
            FunctionResultContent(
              callId: content.callId,
              name: content.name,
              result: jsonEncode(content.result),
              exception: content.exception,
            ),
          );
        } else {
          contents.add(content);
        }
      }
      if (contents.isEmpty) continue;

      final calls = contents.whereType<FunctionCallContent>().toList();
      final hasText = contents.any(
        (c) => c is TextContent && c.text.trim().isNotEmpty,
      );
      if (calls.isNotEmpty && hasText) {
        out.add(
          ChatMessage(
            role: message.role,
            contents: contents.where((c) => c is! FunctionCallContent).toList(),
          ),
        );
        out.add(
          ChatMessage(role: message.role, contents: <AIContent>[...calls]),
        );
      } else {
        out.add(ChatMessage(role: message.role, contents: contents));
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Native mode: response side
  // ---------------------------------------------------------------------

  /// Recovers what the inner client's non-streaming parse discards:
  /// assistant text alongside `tool_calls`, and `reasoning` /
  /// `reasoning_content` fields; splits `<think>` tags when profiled.
  ChatResponse _recoverNativeExtras(ChatResponse response) {
    final message = _rawChoiceMessage(response.rawRepresentation);

    for (var i = 0; i < response.messages.length; i++) {
      final chatMessage = response.messages[i];
      // The inner client may build a List<FunctionCallContent>; copy into
      // a List<AIContent> so mixed content can be added.
      final contents = List<AIContent>.of(chatMessage.contents);

      final reasoning = message?['reasoning'] ?? message?['reasoning_content'];
      if (reasoning is String && reasoning.isNotEmpty) {
        contents.insert(0, TextReasoningContent(reasoning));
      }

      // Assistant prose the inner client dropped next to tool_calls.
      final hasCalls = contents.any((c) => c is FunctionCallContent);
      final content = message?['content'];
      if (hasCalls && content is String && content.isNotEmpty) {
        contents.insert(0, TextContent(content));
      }

      if (_stripThinkTags) {
        _splitThinkTagsInPlace(contents);
      }

      response.messages[i] = ChatMessage(
        role: chatMessage.role,
        contents: contents,
        authorName: chatMessage.authorName,
        createdAt: chatMessage.createdAt,
        messageId: chatMessage.messageId,
        rawRepresentation: chatMessage.rawRepresentation,
        additionalProperties: chatMessage.additionalProperties,
      );
    }
    return response;
  }

  /// Replaces each [TextContent] with the reasoning/text mix produced by
  /// a [ThinkTagFilter] over its text.
  void _splitThinkTagsInPlace(List<AIContent> contents) {
    for (var i = 0; i < contents.length; i++) {
      final content = contents[i];
      if (content is! TextContent) continue;
      final filter = ThinkTagFilter();
      final split = <AIContent>[...filter.add(content.text), ...filter.flush()];
      if (split.length == 1 && split.single is TextContent) continue;
      contents
        ..removeAt(i)
        ..insertAll(i, split);
      i += split.length - 1;
    }
  }

  /// Re-parses each streamed chunk's raw JSON to assemble `tool_calls`
  /// deltas, recover reasoning fields, and split `<think>` tags.
  Stream<ChatResponseUpdate> _decorateNativeStream(
    Stream<ChatResponseUpdate> updates,
  ) async* {
    final pending = <int, _StreamingToolCall>{};
    final think = _stripThinkTags ? ThinkTagFilter() : null;
    ChatResponseUpdate? last;

    await for (final update in updates) {
      last = update;
      final delta = _deltaOf(update.rawRepresentation);

      final contents = <AIContent>[];
      final reasoning = delta?['reasoning'] ?? delta?['reasoning_content'];
      if (reasoning is String && reasoning.isNotEmpty) {
        contents.add(TextReasoningContent(reasoning));
      }

      for (final content in update.contents) {
        if (content is TextContent && think != null) {
          contents.addAll(think.add(content.text));
        } else {
          contents.add(content);
        }
      }

      final toolDeltas = delta?['tool_calls'];
      if (toolDeltas is List) {
        _accumulateToolCalls(pending, toolDeltas);
      }

      // Flush assembled calls when the model signals it is done calling,
      // in a separate update so prose is not suppressed with them.
      if (update.finishReason != null && pending.isNotEmpty) {
        yield _toolCallUpdate(update, _drain(pending));
      }

      yield _cloneWith(update, contents);
    }

    if (think != null) {
      final tail = think.flush();
      if (tail.isNotEmpty) yield _cloneWith(last, tail);
    }
    if (pending.isNotEmpty) {
      yield _toolCallUpdate(last, _drain(pending));
    }
  }

  /// Extracts `choices[0].message` from a raw completion JSON object.
  static Map<String, dynamic>? _rawChoiceMessage(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final choices = raw['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final choice = choices.first;
    if (choice is! Map<String, dynamic>) return null;
    final message = choice['message'];
    return message is Map<String, dynamic> ? message : null;
  }

  static Map<String, dynamic>? _deltaOf(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final choices = raw['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final choice = choices.first;
    if (choice is! Map<String, dynamic>) return null;
    return choice['delta'] as Map<String, dynamic>?;
  }

  static void _accumulateToolCalls(
    Map<int, _StreamingToolCall> pending,
    List<dynamic> deltas,
  ) {
    for (final entry in deltas) {
      if (entry is! Map<String, dynamic>) continue;
      final index = entry['index'] as int? ?? 0;
      final call = pending.putIfAbsent(index, _StreamingToolCall.new);
      final id = entry['id'];
      if (id is String && id.isNotEmpty) call.callId = id;
      final function = entry['function'];
      if (function is Map<String, dynamic>) {
        final name = function['name'];
        if (name is String && name.isNotEmpty) call.name = name;
        final args = function['arguments'];
        if (args is String) call.arguments.write(args);
      }
    }
  }

  static List<FunctionCallContent> _drain(
    Map<int, _StreamingToolCall> pending,
  ) {
    final indices = pending.keys.toList()..sort();
    final calls = [for (final i in indices) pending[i]!.build(i)];
    pending.clear();
    return calls;
  }

  static ChatResponseUpdate _toolCallUpdate(
    ChatResponseUpdate? template,
    List<FunctionCallContent> calls,
  ) => ChatResponseUpdate(
    role: template?.role ?? ChatRole.assistant,
    contents: List<AIContent>.of(calls),
    responseId: template?.responseId,
    messageId: template?.messageId,
    modelId: template?.modelId,
    createdAt: template?.createdAt,
  );

  static ChatResponseUpdate _cloneWith(
    ChatResponseUpdate? template,
    List<AIContent> contents,
  ) {
    final clone = template?.clone() ?? ChatResponseUpdate();
    clone.contents
      ..clear()
      ..addAll(contents);
    return clone;
  }

  // ---------------------------------------------------------------------
  // Prompt-injected fallback
  // ---------------------------------------------------------------------

  /// Moves tool declarations into the system instructions and clears the
  /// request's tool fields.
  ChatOptions _injectedOptions(ChatOptions? options) {
    final result = (options ?? ChatOptions()).clone();
    final section = _toolFormat.renderToolsSection(_declaredTools(options));
    result.instructions = switch (result.instructions) {
      final existing? when existing.isNotEmpty => '$existing\n\n$section',
      _ => section,
    };
    result.tools = null;
    result.toolMode = null;
    result.allowMultipleToolCalls = null;
    return result;
  }

  /// Rewrites tool traffic in history as plain text in the model
  /// family's markup: past calls become assistant text and results
  /// become user text, so the server-side template sees only roles it
  /// understands.
  List<ChatMessage> _rewriteForInjection(Iterable<ChatMessage> messages) {
    final out = <ChatMessage>[];
    for (final message in messages) {
      final parts = <String>[];
      var hasToolTraffic = false;
      var isResult = false;
      for (final content in message.contents) {
        switch (content) {
          case TextContent(:final text) when text.trim().isNotEmpty:
            parts.add(text);
          case FunctionCallContent():
            parts.add(_toolFormat.renderToolCallBlock(content));
            hasToolTraffic = true;
          case FunctionResultContent():
            parts.add(_toolFormat.renderToolResultBlock(content));
            hasToolTraffic = true;
            isResult = true;
          case TextReasoningContent():
            break;
          default:
            // Media and other content passes through unchanged below.
            break;
        }
      }
      if (!hasToolTraffic) {
        final contents = message.contents
            .where((c) => c is! TextReasoningContent)
            .toList();
        if (contents.isNotEmpty) {
          out.add(ChatMessage(role: message.role, contents: contents));
        }
        continue;
      }
      if (parts.isEmpty) continue;
      out.add(
        ChatMessage(
          role: isResult ? ChatRole.user : ChatRole.assistant,
          contents: [TextContent(parts.join('\n'))],
        ),
      );
    }
    return out;
  }

  /// Parses tool calls out of a complete injected-mode response.
  ChatResponse _parseInjectedResponse(ChatResponse response) {
    for (var i = 0; i < response.messages.length; i++) {
      final message = response.messages[i];
      final text = message.text;
      if (text.isEmpty) continue;

      var prose = text;
      final contents = <AIContent>[];
      if (_stripThinkTags) {
        final filter = ThinkTagFilter();
        final split = [...filter.add(text), ...filter.flush()];
        contents.addAll(split.whereType<TextReasoningContent>());
        prose = split.whereType<TextContent>().map((c) => c.text).join();
      }

      ParsedToolTurn turn;
      try {
        turn = _toolFormat.parseTurn(prose);
      } on FormatException {
        turn = ParsedToolTurn(text: prose, calls: const []);
      }
      if (turn.text.isNotEmpty) contents.add(TextContent(turn.text));
      contents.addAll(turn.calls);

      response.messages[i] = ChatMessage(
        role: message.role,
        contents: [
          ...message.contents.where((c) => c is! TextContent),
          ...contents,
        ],
        authorName: message.authorName,
        createdAt: message.createdAt,
        messageId: message.messageId,
        rawRepresentation: message.rawRepresentation,
        additionalProperties: message.additionalProperties,
      );
    }
    final hasCalls = response.messages.any(
      (m) => m.contents.any((c) => c is FunctionCallContent),
    );
    if (hasCalls) {
      return _withFinishReason(response, ChatFinishReason.toolCalls);
    }
    return response;
  }

  static ChatResponse _withFinishReason(
    ChatResponse response,
    ChatFinishReason reason,
  ) => ChatResponse(
    messages: response.messages,
    responseId: response.responseId,
    conversationId: response.conversationId,
    modelId: response.modelId,
    createdAt: response.createdAt,
    finishReason: reason,
    usage: response.usage,
    rawRepresentation: response.rawRepresentation,
    additionalProperties: response.additionalProperties,
  );

  /// Runs streamed injected-mode text through the think-tag filter and
  /// the family's incremental tool-call decoder.
  Stream<ChatResponseUpdate> _decodeInjectedStream(
    Stream<ChatResponseUpdate> updates,
  ) async* {
    final decoder = _toolFormat.newStreamDecoder();
    final think = _stripThinkTags ? ThinkTagFilter() : null;
    ChatResponseUpdate? last;

    await for (final update in updates) {
      last = update;
      final contents = <AIContent>[];
      for (final content in update.contents) {
        if (content is! TextContent) {
          contents.add(content);
          continue;
        }
        final pieces = think != null
            ? think.add(content.text)
            : <AIContent>[content];
        for (final piece in pieces) {
          if (piece is TextContent) {
            final prose = decoder.add(piece.text);
            if (prose.isNotEmpty) contents.add(TextContent(prose));
          } else {
            contents.add(piece);
          }
        }
      }
      // Suppress the server's finish reason: whether this turn is a tool
      // call is only known once the buffered tail is parsed.
      final clone = _cloneWith(update, contents);
      clone.finishReason = null;
      yield clone;
    }

    if (think != null) {
      for (final piece in think.flush()) {
        if (piece is TextContent) {
          final prose = decoder.add(piece.text);
          if (prose.isNotEmpty) yield _cloneWith(last, [TextContent(prose)]);
        } else {
          yield _cloneWith(last, [piece]);
        }
      }
    }

    final turn = decoder.finish();
    if (turn.text.isNotEmpty) {
      yield _cloneWith(last, [TextContent(turn.text)]);
    }
    if (turn.calls.isNotEmpty) {
      yield _toolCallUpdate(last, turn.calls);
    }
    final finish = ChatResponseUpdate(
      role: last?.role ?? ChatRole.assistant,
      finishReason: turn.calls.isNotEmpty
          ? ChatFinishReason.toolCalls
          : (last?.finishReason ?? ChatFinishReason.stop),
      responseId: last?.responseId,
      modelId: last?.modelId,
    );
    yield finish;
  }
}

/// Assembles one streamed `tool_calls` entry across chunks.
class _StreamingToolCall {
  String callId = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();

  /// Builds the final content; a malformed arguments payload is attached
  /// as the content's exception rather than thrown.
  FunctionCallContent build(int index) {
    Map<String, Object?>? args;
    Exception? failure;
    final raw = arguments.toString();
    if (raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          args = decoded.cast<String, Object?>();
        } else {
          failure = FormatException(
            'Tool call arguments are not a JSON object',
            raw,
          );
        }
      } on FormatException catch (error) {
        failure = error;
      }
    }
    final content = FunctionCallContent(
      callId: callId.isEmpty ? 'call_$index' : callId,
      name: name,
      arguments: args,
    );
    if (failure != null) content.exception = failure;
    return content;
  }
}
