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

    test('round-trips uri content', () {
      final message = ChatMessage(
        role: ChatRole.user,
        contents: [
          UriContent(
            Uri.parse('https://example.com/report.pdf'),
            mediaType: 'application/pdf',
          ),
        ],
      );

      final decoded = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      )!.contents.single;

      expect(
        (decoded as UriContent).uri.toString(),
        'https://example.com/report.pdf',
      );
      expect(decoded.mediaType, 'application/pdf');
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

    test('sanitizes non-JSON argument values per entry', () {
      final message = ChatMessage(
        role: ChatRole.assistant,
        contents: [
          FunctionCallContent(
            callId: 'call-1',
            name: 'do_thing',
            arguments: {'good': 42, 'bad': _NotJson()},
          ),
        ],
      );

      final decoded = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      );

      final call = decoded!.contents.whereType<FunctionCallContent>().single;
      expect(call.arguments, {'good': 42, 'bad': 'opaque-result'});
    });

    test('sanitizes non-JSON values nested in argument lists', () {
      final message = ChatMessage(
        role: ChatRole.assistant,
        contents: [
          FunctionCallContent(
            callId: 'call-1',
            name: 'do_thing',
            arguments: {
              'items': [1, _NotJson()],
            },
          ),
        ],
      );

      final decoded = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      );

      final call = decoded!.contents.whereType<FunctionCallContent>().single;
      expect(call.arguments, {
        'items': [1, 'opaque-result'],
      });
    });

    test('does not hang on cyclic argument structures', () {
      final cycle = <String, Object?>{};
      cycle['self'] = cycle;
      final message = ChatMessage(
        role: ChatRole.assistant,
        contents: [
          FunctionCallContent(callId: 'call-1', name: 'f', arguments: cycle),
        ],
      );

      final decoded = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      );

      final call = decoded!.contents.whereType<FunctionCallContent>().single;
      expect(call.arguments, {'self': '<cyclic>'});
    });

    test('decodes legacy records whose arguments were stringified whole', () {
      final decoded = ChatMessageCodec.decode({
        'v': 1,
        'role': 'assistant',
        'contents': [
          {
            'kind': 'functionCall',
            'callId': 'call-1',
            'name': 'do_thing',
            'arguments': '{bad: map}',
          },
        ],
      });

      final call = decoded!.contents.whereType<FunctionCallContent>().single;
      expect(call.arguments, {'value': '{bad: map}'});
    });

    test('round-trips function result exceptions', () {
      final message = ChatMessage(
        role: ChatRole.tool,
        contents: [
          FunctionResultContent(
            callId: 'call-1',
            name: 'do_thing',
            exception: Exception('tool blew up'),
          ),
        ],
      );

      final once = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      )!;
      final twice = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(once)),
      )!;

      final result = twice.contents.whereType<FunctionResultContent>().single;
      expect(result.exception, isNotNull);
      expect(result.exception.toString(), 'Exception: tool blew up');
    });

    test('round-trips data content with a null media type', () {
      final message = ChatMessage(
        role: ChatRole.user,
        contents: [
          DataContent(Uint8List.fromList([9, 8, 7]), mediaType: null),
        ],
      );

      final decoded = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      )!.contents.single;

      expect((decoded as DataContent).data, [9, 8, 7]);
      expect(decoded.mediaType, isNull);
    });

    test('round-trips data content holding an external uri', () {
      final message = ChatMessage(
        role: ChatRole.user,
        contents: [
          DataContent.fromUri('https://example.com/image.png', name: 'pic'),
        ],
      );

      final decoded = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      )!.contents.single;

      expect((decoded as DataContent).uri, 'https://example.com/image.png');
      expect(decoded.data, isNull);
      expect(decoded.name, 'pic');
    });

    test('drops empty data content without losing the message', () {
      final message = ChatMessage(
        role: ChatRole.user,
        contents: [
          TextContent('see attachment'),
          DataContent(null, mediaType: 'image/png'),
        ],
      );

      final decoded = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      );

      expect(decoded, isNotNull);
      expect(decoded!.text, 'see attachment');
      expect(decoded.contents.whereType<DataContent>(), isEmpty);
    });

    test('round-trips usage additional counts', () {
      final message = ChatMessage(
        role: ChatRole.assistant,
        contents: [
          UsageContent(
            UsageDetails(
              inputTokenCount: 10,
              additionalCounts: {'audio': 3, 'image': 7},
            ),
          ),
        ],
      );

      final decoded = ChatMessageCodec.decode(
        _jsonRoundTrip(ChatMessageCodec.encode(message)),
      );

      final usage = decoded!.contents.whereType<UsageContent>().single;
      expect(usage.details.inputTokenCount, 10);
      expect(usage.details.additionalCounts, {'audio': 3, 'image': 7});
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
