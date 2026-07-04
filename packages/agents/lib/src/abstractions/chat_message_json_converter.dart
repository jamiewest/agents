import 'dart:convert';
import 'dart:developer' as developer;

import 'package:extensions/ai.dart';

/// Provides JSON encode/decode helpers for framework [ChatMessage]s.
///
/// Upstream C# serializes `ChatMessage` (and its polymorphic `AIContent`
/// list) through the reflection-based `System.Text.Json` contract exposed by
/// `AgentAbstractionsJsonUtilities`. Dart has no runtime reflection, so this
/// converter provides the explicit equivalent for the content kinds that
/// matter when resuming a conversation: text, reasoning text, function calls,
/// function results, data/attachment references, URIs, and errors. Content
/// kinds the converter does not understand are dropped with a debug log
/// rather than failing the whole message.
class ChatMessageJsonConverter {
  ChatMessageJsonConverter._();

  static const String _logName = 'agents.abstractions.chat_message_json';

  /// Encodes [message] to a JSON-compatible map.
  static Map<String, Object?> encode(ChatMessage message) => {
    'role': message.role.value,
    if (message.authorName != null) 'authorName': message.authorName,
    if (message.messageId != null) 'messageId': message.messageId,
    if (message.createdAt != null)
      'createdAt': message.createdAt!.toUtc().toIso8601String(),
    'contents': [
      for (final content in message.contents) ?_encodeContent(content),
    ],
  };

  /// Decodes a map produced by [encode].
  ///
  /// Returns `null` when the payload is malformed, so callers can skip
  /// corrupt records instead of failing the whole restore.
  static ChatMessage? decode(Map<String, Object?> json) {
    try {
      final createdAt = json['createdAt'] as String?;
      return ChatMessage(
        role: ChatRole(json['role']! as String),
        authorName: json['authorName'] as String?,
        messageId: json['messageId'] as String?,
        createdAt: createdAt == null ? null : DateTime.parse(createdAt),
        contents: [
          for (final entry in json['contents']! as List<Object?>)
            ?_decodeContent((entry! as Map).cast<String, Object?>()),
        ],
      );
    } catch (error, stackTrace) {
      developer.log(
        'Ignoring corrupt serialized chat message.',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Encodes [messages] to a JSON-compatible list.
  static List<Object?> encodeList(Iterable<ChatMessage> messages) => [
    for (final message in messages) encode(message),
  ];

  /// Decodes a list produced by [encodeList], skipping corrupt entries.
  static List<ChatMessage> decodeList(Object? json) => [
    if (json is List)
      for (final entry in json)
        if (entry is Map) ?decode(entry.cast<String, Object?>()),
  ];

  static Map<String, Object?>? _encodeContent(AIContent content) =>
      switch (content) {
        TextContent(:final text) => {'kind': 'text', 'text': text},
        TextReasoningContent(:final text) => {
          'kind': 'textReasoning',
          'text': text,
        },
        FunctionCallContent(:final callId, :final name, :final arguments) => {
          'kind': 'functionCall',
          'callId': callId,
          'name': name,
          if (arguments != null) 'arguments': _jsonSafe(arguments),
        },
        FunctionResultContent(
          :final callId,
          :final name,
          :final result,
          :final exception,
        ) =>
          {
            'kind': 'functionResult',
            'callId': callId,
            'name': ?name,
            if (result != null) 'result': _jsonSafe(result),
            if (exception != null) 'exception': exception.toString(),
          },
        DataContent(:final uri, :final data, :final mediaType, :final name) => {
          'kind': 'data',
          'uri': ?uri,
          if (uri == null && data != null) 'bytes': base64Encode(data),
          'mediaType': ?mediaType,
          'name': ?name,
        },
        UriContent(:final uri, :final mediaType) => {
          'kind': 'uri',
          'uri': uri.toString(),
          'mediaType': mediaType,
        },
        ErrorContent(:final message, :final errorCode, :final details) => {
          'kind': 'error',
          'message': message,
          'errorCode': ?errorCode,
          'details': ?details,
        },
        _ => _logDropped(content),
      };

  static Map<String, Object?>? _logDropped(AIContent content) {
    developer.log(
      'Dropping unsupported content type ${content.runtimeType} from '
      'serialized chat message.',
      name: _logName,
    );
    return null;
  }

  static AIContent? _decodeContent(Map<String, Object?> json) =>
      switch (json['kind']) {
        'text' => TextContent(json['text']! as String),
        'textReasoning' => TextReasoningContent(json['text']! as String),
        'functionCall' => FunctionCallContent(
          callId: json['callId']! as String,
          name: json['name']! as String,
          arguments: (json['arguments'] as Map?)?.cast<String, Object?>(),
        ),
        'functionResult' => FunctionResultContent(
          callId: json['callId']! as String,
          name: json['name'] as String?,
          result: json['result'],
        ),
        'data' => switch (json['uri']) {
          final String uri => DataContent.fromUri(
            uri,
            name: json['name'] as String?,
          ),
          _ => DataContent(
            base64Decode(json['bytes']! as String),
            mediaType: json['mediaType'] as String?,
            name: json['name'] as String?,
          ),
        },
        'uri' => UriContent(
          Uri.parse(json['uri']! as String),
          mediaType: json['mediaType']! as String,
        ),
        'error' => ErrorContent(
          json['message']! as String,
          errorCode: json['errorCode'] as String?,
          details: json['details'] as String?,
        ),
        _ => null,
      };

  /// Returns [value] if it survives JSON encoding, otherwise its string form.
  static Object? _jsonSafe(Object? value) {
    try {
      jsonEncode(value);
      return value;
    } on Object {
      return value.toString();
    }
  }
}
