// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextFileInliningChatClient', () {
    test('replaces text-like DataContent with a tagged text block', () async {
      final capturing = _CapturingChatClient();
      final client = TextFileInliningChatClient(capturing);
      final csvBytes = Uint8List.fromList(utf8.encode('a,b\n1,2'));
      final message = ChatMessage(
        role: ChatRole.user,
        contents: [
          TextContent('summarize this'),
          DataContent(csvBytes, mediaType: 'text/csv', name: 'data.csv'),
        ],
      );

      await client.getResponse(messages: [message]);

      final sent = capturing.lastMessages!.single;
      expect(sent.contents, hasLength(2));
      expect(sent.contents.whereType<DataContent>(), isEmpty);
      final inlined = sent.contents[1] as TextContent;
      expect(inlined.text, contains('name="data.csv"'));
      expect(inlined.text, contains('media-type="text/csv"'));
      expect(inlined.text, contains('a,b\n1,2'));
    });

    test('does not mutate the caller\'s message', () async {
      final capturing = _CapturingChatClient();
      final client = TextFileInliningChatClient(capturing);
      final message = ChatMessage(
        role: ChatRole.user,
        contents: [
          DataContent(
            Uint8List.fromList(utf8.encode('{}')),
            mediaType: 'application/json',
            name: 'config.json',
          ),
        ],
      );

      await client.getResponse(messages: [message]);

      expect(message.contents.single, isA<DataContent>());
      expect(capturing.lastMessages!.single, isNot(same(message)));
    });

    test('passes images and untouched messages through unchanged', () async {
      final capturing = _CapturingChatClient();
      final client = TextFileInliningChatClient(capturing);
      final image = ChatMessage(
        role: ChatRole.user,
        contents: [
          DataContent(
            Uint8List.fromList([1, 2, 3]),
            mediaType: 'image/png',
            name: 'photo.png',
          ),
        ],
      );
      final plain = ChatMessage.fromText(ChatRole.user, 'hello');

      await for (final _ in client.getStreamingResponse(
        messages: [plain, image],
      )) {}

      final sent = capturing.lastMessages!;
      expect(sent[0], same(plain));
      expect(sent[1], same(image));
      expect(sent[1].contents.single, isA<DataContent>());
    });

    test('isTextLike classifies media types', () {
      expect(TextFileInliningChatClient.isTextLike('text/plain'), isTrue);
      expect(TextFileInliningChatClient.isTextLike('text/csv'), isTrue);
      expect(
        TextFileInliningChatClient.isTextLike('text/csv; charset=utf-8'),
        isTrue,
      );
      expect(TextFileInliningChatClient.isTextLike('application/json'), isTrue);
      expect(
        TextFileInliningChatClient.isTextLike('application/ld+json'),
        isTrue,
      );
      expect(TextFileInliningChatClient.isTextLike('image/png'), isFalse);
      expect(TextFileInliningChatClient.isTextLike('application/pdf'), isFalse);
      expect(TextFileInliningChatClient.isTextLike(null), isFalse);
    });
  });
}

final class _CapturingChatClient implements ChatClient {
  List<ChatMessage>? lastMessages;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    lastMessages = messages.toList();
    return ChatResponse(
      messages: [ChatMessage.fromText(ChatRole.assistant, 'ok')],
    );
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) {
    lastMessages = messages.toList();
    return const Stream.empty();
  }

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}
}
