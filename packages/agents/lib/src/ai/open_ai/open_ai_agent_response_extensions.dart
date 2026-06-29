// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Microsoft.Agents.AI.OpenAI/Extensions/AgentResponseExtensions.cs
// and the streaming collection-result adapters. Dart does not expose native
// OpenAI SDK model types here, so the adapter uses OpenAI wire-shape maps.

import 'dart:convert';

import 'package:extensions/ai.dart';

import '../../abstractions/agent_response.dart';
import '../../abstractions/agent_response_extensions.dart';
import '../../abstractions/agent_response_update.dart';

/// OpenAI conversion helpers for [AgentResponse].
extension OpenAIAgentResponseExtensions on AgentResponse {
  /// Creates or extracts an OpenAI chat-completion JSON object.
  Map<String, dynamic> asOpenAIChatCompletion() {
    final raw = _rawMap(rawRepresentation);
    if (raw != null) {
      return raw;
    }
    return _chatCompletionFromChatResponse(_asChatResponseWithAgentMetadata());
  }

  /// Creates or extracts an OpenAI Responses API JSON object.
  Map<String, dynamic> asOpenAIResponse() {
    final raw = _rawMap(rawRepresentation);
    if (raw != null && _isOpenAIResponseMap(raw)) {
      return raw;
    }

    final chatResponse = _asChatResponseWithAgentMetadata();
    final chatRaw = _rawMap(chatResponse.rawRepresentation);
    if (chatRaw != null && _isOpenAIResponseMap(chatRaw)) {
      return chatRaw;
    }

    return _responseFromChatResponse(chatResponse);
  }
}

extension on AgentResponse {
  ChatResponse _asChatResponseWithAgentMetadata() {
    final chatResponse = asChatResponse();
    chatResponse.responseId ??= responseId;
    chatResponse.createdAt ??= createdAt;
    chatResponse.finishReason ??= finishReason;
    chatResponse.usage ??= usage;
    chatResponse.continuationToken ??= continuationToken;
    return chatResponse;
  }
}

/// OpenAI conversion helpers for [Stream]s of [AgentResponseUpdate].
extension OpenAIAgentResponseUpdateStreamExtensions
    on Stream<AgentResponseUpdate> {
  /// Converts agent updates to OpenAI chat-completion chunk JSON objects.
  Stream<Map<String, dynamic>> asOpenAIStreamingChatCompletionUpdates() async* {
    await for (final update in this) {
      final raw = _rawMap(update.rawRepresentation);
      if (raw != null) {
        yield raw;
        continue;
      }
      yield _chatCompletionChunkFromUpdate(update.asChatResponseUpdate());
    }
  }

  /// Emits raw OpenAI Responses API streaming-event maps when present.
  ///
  /// The upstream OpenAI SDK does not expose factories for Responses streaming
  /// updates. Matching that behavior, this skips updates that do not already
  /// carry a Responses event as their raw representation.
  Stream<Map<String, dynamic>> asOpenAIStreamingResponseUpdates() async* {
    await for (final update in this) {
      final raw = _rawMap(update.rawRepresentation);
      if (raw != null && _isOpenAIResponseMap(raw)) {
        yield raw;
      }
    }
  }
}

Map<String, dynamic> _chatCompletionFromChatResponse(ChatResponse response) {
  final created = _unixSeconds(response.createdAt);
  final result = <String, dynamic>{
    'id': response.responseId ?? _fallbackId('chatcmpl', response),
    'object': 'chat.completion',
    if (response.modelId != null) 'model': response.modelId,
    'choices': [
      for (var i = 0; i < response.messages.length; i++)
        {
          'index': i,
          'message': _messageToOpenAI(response.messages[i]),
          'finish_reason': i == response.messages.length - 1
              ? response.finishReason?.value
              : null,
        },
    ],
    if (response.usage != null) 'usage': _usageToOpenAI(response.usage!),
  };
  if (created != null) {
    result['created'] = created;
  }
  return result;
}

Map<String, dynamic> _chatCompletionChunkFromUpdate(ChatResponseUpdate update) {
  final created = _unixSeconds(update.createdAt);
  final result = <String, dynamic>{
    'id': update.responseId ?? _fallbackId('chatcmpl', update),
    'object': 'chat.completion.chunk',
    if (update.modelId != null) 'model': update.modelId,
    'choices': update.usage != null && update.contents.isEmpty
        ? const []
        : [
            {
              'index': 0,
              'delta': _deltaToOpenAI(update),
              'finish_reason': update.finishReason?.value,
            },
          ],
    if (update.usage != null) 'usage': _usageToOpenAI(update.usage!),
  };
  if (created != null) {
    result['created'] = created;
  }
  return result;
}

Map<String, dynamic> _responseFromChatResponse(ChatResponse response) {
  final created = _unixSeconds(response.createdAt);
  final result = <String, dynamic>{
    'id': response.responseId ?? _fallbackId('resp', response),
    'object': 'response',
    if (response.modelId != null) 'model': response.modelId,
    'status': 'completed',
    'output': [
      for (final message in response.messages)
        {
          'type': 'message',
          'role': message.role.value,
          'content': [
            for (final content in message.contents.whereType<TextContent>())
              {'type': 'output_text', 'text': content.text},
          ],
        },
    ],
    if (response.usage != null) 'usage': _usageToResponses(response.usage!),
  };
  if (created != null) {
    result['created_at'] = created;
  }
  return result;
}

Map<String, dynamic> _messageToOpenAI(ChatMessage message) {
  final result = <String, dynamic>{'role': message.role.value};

  final functionResults = message.contents.whereType<FunctionResultContent>();
  if (functionResults.isNotEmpty) {
    final first = functionResults.first;
    result['tool_call_id'] = first.callId;
    result['content'] = first.result?.toString() ?? '';
    return result;
  }

  final toolCalls = message.contents.whereType<FunctionCallContent>().toList();
  if (toolCalls.isNotEmpty) {
    result['tool_calls'] = [
      for (final call in toolCalls)
        {
          'id': call.callId,
          'type': 'function',
          'function': {
            'name': call.name,
            'arguments': jsonEncode(
              call.arguments ?? const <String, Object?>{},
            ),
          },
        },
    ];
    return result;
  }

  result['content'] = message.text;
  return result;
}

Map<String, dynamic> _deltaToOpenAI(ChatResponseUpdate update) {
  final result = <String, dynamic>{};
  if (update.role != null) {
    result['role'] = update.role!.value;
  }
  final text = update.text;
  if (text.isNotEmpty) {
    result['content'] = text;
  }
  return result;
}

Map<String, dynamic> _usageToOpenAI(UsageDetails usage) => {
  if (usage.inputTokenCount != null) 'prompt_tokens': usage.inputTokenCount,
  if (usage.outputTokenCount != null)
    'completion_tokens': usage.outputTokenCount,
  if (usage.totalTokenCount != null) 'total_tokens': usage.totalTokenCount,
  if (usage.reasoningTokenCount != null)
    'completion_tokens_details': {
      'reasoning_tokens': usage.reasoningTokenCount,
    },
  if (usage.cachedInputTokenCount != null)
    'prompt_tokens_details': {'cached_tokens': usage.cachedInputTokenCount},
};

Map<String, dynamic> _usageToResponses(UsageDetails usage) => {
  if (usage.inputTokenCount != null) 'input_tokens': usage.inputTokenCount,
  if (usage.outputTokenCount != null) 'output_tokens': usage.outputTokenCount,
  if (usage.totalTokenCount != null) 'total_tokens': usage.totalTokenCount,
  if (usage.reasoningTokenCount != null)
    'output_tokens_details': {'reasoning_tokens': usage.reasoningTokenCount},
};

Map<String, dynamic>? _rawMap(Object? raw, [int depth = 0]) {
  if (raw == null || depth > 4) {
    return null;
  }
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  if (raw is Map) {
    return {
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  if (raw is AgentResponse) {
    return _rawMap(raw.rawRepresentation, depth + 1);
  }
  if (raw is AgentResponseUpdate) {
    return _rawMap(raw.rawRepresentation, depth + 1);
  }
  if (raw is ChatResponse) {
    return _rawMap(raw.rawRepresentation, depth + 1);
  }
  if (raw is ChatResponseUpdate) {
    return _rawMap(raw.rawRepresentation, depth + 1);
  }
  return null;
}

bool _isOpenAIResponseMap(Map<String, dynamic> map) {
  final type = map['type'];
  if (type is String && type.startsWith('response.')) {
    return true;
  }
  final object = map['object'];
  return object == 'response' ||
      object == 'response.input_item' ||
      object == 'response.deleted';
}

int? _unixSeconds(DateTime? dateTime) =>
    dateTime == null ? null : dateTime.toUtc().millisecondsSinceEpoch ~/ 1000;

String _fallbackId(String prefix, Object source) =>
    '${prefix}_${source.hashCode.toUnsigned(32).toRadixString(16)}';
