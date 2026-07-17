// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:extensions/ai.dart';

/// Encodes and decodes framework [ChatMessage]s as JSON-compatible maps.
///
/// Persists the content kinds that matter for resuming model context —
/// text, function calls, function results, data and link attachments, and
/// token usage — so a restored conversation replays tool use faithfully and
/// keeps per-message usage detail. Content kinds the codec does not
/// understand are dropped with a debug log rather than failing the whole
/// message.
class ChatMessageCodec {
  ChatMessageCodec._();

  /// The schema version written by [encode].
  static const int schemaVersion = 1;

  /// Encodes [message] to a JSON-compatible map.
  static Map<String, Object?> encode(ChatMessage message) => {
    'v': schemaVersion,
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
  /// Returns `null` when the payload is malformed or has an unknown schema
  /// version, so callers can skip corrupt records.
  static ChatMessage? decode(Map<String, Object?> json) {
    try {
      if (json['v'] != schemaVersion) {
        return null;
      }
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
    } catch (e, s) {
      developer.log(
        'Ignoring corrupt persisted chat message.',
        name: 'agents_flutter.chat_history',
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }

  static Map<String, Object?>? _encodeContent(AIContent content) =>
      switch (content) {
        TextContent(:final text) => {'kind': 'text', 'text': text},
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
        // Bytes are preferred over the synthesized data URI so a null
        // mediaType round-trips as null instead of the URI default
        // (application/octet-stream). External (non-data) URIs carry no
        // bytes and keep the URI form.
        DataContent(:final uri, :final data, :final mediaType, :final name) => {
          'kind': 'data',
          if (data != null) 'bytes': base64Encode(data) else 'uri': ?uri,
          'mediaType': ?mediaType,
          'name': ?name,
        },
        UriContent(:final uri, :final mediaType) => {
          'kind': 'uri',
          'uri': '$uri',
          'mediaType': mediaType,
        },
        UsageContent(:final details) => _encodeUsage(details),
        _ => _logDropped(content),
      };

  static Map<String, Object?> _encodeUsage(UsageDetails details) {
    if (details.additionalProperties != null) {
      developer.log(
        'Dropping UsageDetails.additionalProperties from persisted chat '
        'history.',
        name: 'agents_flutter.chat_history',
      );
    }
    return {
      'kind': 'usage',
      if (details.inputTokenCount != null) 'input': details.inputTokenCount,
      if (details.outputTokenCount != null) 'output': details.outputTokenCount,
      if (details.totalTokenCount != null) 'total': details.totalTokenCount,
      if (details.cachedInputTokenCount != null)
        'cached': details.cachedInputTokenCount,
      if (details.reasoningTokenCount != null)
        'reasoning': details.reasoningTokenCount,
      'counts': ?details.additionalCounts,
    };
  }

  static Map<String, Object?>? _logDropped(AIContent content) {
    developer.log(
      'Dropping unsupported content type ${content.runtimeType} from '
      'persisted chat history.',
      name: 'agents_flutter.chat_history',
    );
    return null;
  }

  static AIContent? _decodeContent(Map<String, Object?> json) =>
      switch (json['kind']) {
        'text' => TextContent(json['text']! as String),
        'functionCall' => FunctionCallContent(
          callId: json['callId']! as String,
          name: json['name']! as String,
          // Records written before per-entry sanitization may hold the
          // whole arguments map stringified; keep those loadable.
          arguments: switch (json['arguments']) {
            final Map arguments => arguments.cast<String, Object?>(),
            final String arguments => {'value': arguments},
            _ => null,
          },
        ),
        'functionResult' => FunctionResultContent(
          callId: json['callId']! as String,
          name: json['name'] as String?,
          result: json['result'],
          exception: switch (json['exception']) {
            final String message => Exception(
              message.startsWith(_exceptionPrefix)
                  ? message.substring(_exceptionPrefix.length)
                  : message,
            ),
            _ => null,
          },
        ),
        'uri' => UriContent(
          Uri.parse(json['uri']! as String),
          mediaType: json['mediaType']! as String,
        ),
        'usage' => UsageContent(
          UsageDetails(
            inputTokenCount: json['input'] as int?,
            outputTokenCount: json['output'] as int?,
            totalTokenCount: json['total'] as int?,
            cachedInputTokenCount: json['cached'] as int?,
            reasoningTokenCount: json['reasoning'] as int?,
            additionalCounts: (json['counts'] as Map?)?.cast<String, int>(),
          ),
        ),
        'data' => switch ((json['bytes'], json['uri'])) {
          (final String bytes, _) => DataContent(
            base64Decode(bytes),
            mediaType: json['mediaType'] as String?,
            name: json['name'] as String?,
          ),
          (_, final String uri) => DataContent.fromUri(
            uri,
            name: json['name'] as String?,
          ),
          _ => null,
        },
        _ => null,
      };

  static const String _exceptionPrefix = 'Exception: ';

  /// Returns [value] if it survives JSON encoding, otherwise a sanitized
  /// copy.
  ///
  /// Maps and lists are sanitized per entry so a single non-encodable value
  /// does not stringify the whole structure — decode relies on `arguments`
  /// staying a map. Anything else falls back to its string form.
  static Object? _jsonSafe(Object? value) =>
      _jsonSafeInner(value, Set.identity());

  static Object? _jsonSafeInner(Object? value, Set<Object> seen) {
    try {
      jsonEncode(value);
      return value;
    } on Object {
      if (value is Map || value is List) {
        if (!seen.add(value!)) {
          return '<cyclic>';
        }
      }
      return switch (value) {
        final Map map => {
          for (final entry in map.entries)
            '${entry.key}': _jsonSafeInner(entry.value, seen),
        },
        final List list => [
          for (final element in list) _jsonSafeInner(element, seen),
        ],
        _ => value.toString(),
      };
    }
  }
}
