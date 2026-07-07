// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessageCodec', () {
    test('round-trips a text message with metadata', () {
      final message = ChatMessage.fromText(ChatRole.user, 'hello there')
        ..authorName = 'jamie'
        ..messageId = 'msg-1'
        ..createdAt = DateTime.utc(2026, 7, 2, 12);

      final decoded = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      );

      expect(decoded!.role, ChatRole.user);
      expect(decoded.text, 'hello there');
      expect(decoded.authorName, 'jamie');
      expect(decoded.messageId, 'msg-1');
      expect(decoded.createdAt, DateTime.utc(2026, 7, 2, 12));
    });

    test('round-trips function call and result contents', () {
      final message = ChatMessage(
        role: ChatRole.assistant,
        contents: [
          TextContent('Let me check.'),
          FunctionCallContent(
            callId: 'call-1',
            name: 'get_weather',
            arguments: {'zip': '98052', 'units': 'metric'},
          ),
          FunctionResultContent(
            callId: 'call-1',
            name: 'get_weather',
            result: {'tempC': 21},
          ),
        ],
      );

      final decoded = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      );

      final call = decoded!.contents.whereType<FunctionCallContent>().single;
      final result = decoded.contents.whereType<FunctionResultContent>().single;
      expect(call.callId, 'call-1');
      expect(call.name, 'get_weather');
      expect(call.arguments, {'zip': '98052', 'units': 'metric'});
      expect(result.callId, 'call-1');
      expect(result.result, {'tempC': 21});
      expect(decoded.text, 'Let me check.');
    });

    test('round-trips data content by uri and by bytes', () {
      final byUri = ChatMessage(
        role: ChatRole.user,
        contents: [DataContent.fromUri('data:image/png;base64,AAAA')],
      );
      final byBytes = ChatMessage(
        role: ChatRole.user,
        contents: [
          DataContent(
            Uint8List.fromList([1, 2, 3]),
            mediaType: 'application/octet-stream',
            name: 'blob.bin',
          ),
        ],
      );

      final decodedUri = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(byUri)),
      )!.contents.single;
      final decodedBytes = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(byBytes)),
      )!.contents.single;

      expect((decodedUri as DataContent).uri, 'data:image/png;base64,AAAA');
      expect((decodedBytes as DataContent).data, [1, 2, 3]);
      expect(decodedBytes.mediaType, 'application/octet-stream');
      expect(decodedBytes.name, 'blob.bin');
    });

    test('stringifies function results that are not JSON-encodable', () {
      final message = ChatMessage(
        role: ChatRole.tool,
        contents: [FunctionResultContent(callId: 'call-1', result: _NotJson())],
      );

      final decoded = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      );

      final result = decoded!.contents
          .whereType<FunctionResultContent>()
          .single;
      expect(result.result, 'opaque-result');
    });

    test('round-trips usage content', () {
      final message = ChatMessage(
        role: ChatRole.assistant,
        contents: [
          TextContent('answer'),
          UsageContent(
            UsageDetails(
              inputTokenCount: 120,
              outputTokenCount: 45,
              totalTokenCount: 165,
              cachedInputTokenCount: 80,
              reasoningTokenCount: 12,
            ),
          ),
        ],
      );

      final decoded = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      );

      final usage = decoded!.contents.whereType<UsageContent>().single;
      expect(usage.details.inputTokenCount, 120);
      expect(usage.details.outputTokenCount, 45);
      expect(usage.details.totalTokenCount, 165);
      expect(usage.details.cachedInputTokenCount, 80);
      expect(usage.details.reasoningTokenCount, 12);
      expect(decoded.text, 'answer');
    });

    test('tolerates usage payloads with missing counts', () {
      final decoded = ChatMessageCodec.decode({
        'v': 1,
        'role': 'assistant',
        'contents': [
          {'kind': 'usage', 'input': 5},
        ],
      });

      final usage = decoded!.contents.whereType<UsageContent>().single;
      expect(usage.details.inputTokenCount, 5);
      expect(usage.details.outputTokenCount, isNull);
      expect(usage.details.totalTokenCount, isNull);
    });

    test('returns null for unknown schema versions and corrupt maps', () {
      expect(ChatMessageCodec.decode({'v': 99, 'role': 'user'}), isNull);
      expect(ChatMessageCodec.decode({'v': 1}), isNull);
    });
  });
}

/// Encodes to a JSON string and back, proving the map is JSON-compatible.
Map<String, Object?> _jsonRoundTrip(Map<String, Object?> map) =>
    (jsonDecode(jsonEncode(map)) as Map).cast<String, Object?>();

class _NotJson {
  @override
  String toString() => 'opaque-result';
}
