// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: non_constant_identifier_names

import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterChatHistoryProvider', () {
    late InMemoryRecordStore store;
    late _TestAgent agent;
    late AgentSession session;

    setUp(() {
      store = InMemoryRecordStore();
      agent = _TestAgent();
      session = _TestSession();
    });

    FlutterChatHistoryProvider provider({
      String conversationId = 'c1',
      String sessionId = 's1',
      String? senderAgentId,
    }) => FlutterChatHistoryProvider(
      store,
      conversationId: conversationId,
      sessionIdResolver: () => sessionId,
      senderAgentId: senderAgentId,
    );

    Future<void> invoke(
      FlutterChatHistoryProvider target, {
      required List<ChatMessage> request,
      required List<ChatMessage> response,
    }) => target.invoked(
      InvokedContext(agent, session, request, responseMessages: response),
    );

    test('stores an invocation and provides it back in order', () async {
      final target = provider();
      final toolTurn = ChatMessage(
        role: ChatRole.assistant,
        contents: [
          FunctionCallContent(
            callId: 'call-1',
            name: 'lookup',
            arguments: {'q': 'x'},
          ),
        ],
      );

      await invoke(
        target,
        request: [ChatMessage.fromText(ChatRole.user, 'first question')],
        response: [toolTurn, ChatMessage.fromText(ChatRole.assistant, 'ans')],
      );
      final history = (await target.provideChatHistory(
        InvokingContext(agent, session, const []),
      )).toList();

      expect(history, hasLength(3));
      expect(history[0].text, 'first question');
      expect(
        history[1].contents.whereType<FunctionCallContent>().single.name,
        'lookup',
      );
      expect(history[2].text, 'ans');
    });

    test('appends across invocations and sessions (stitched)', () async {
      var sessionId = 's1';
      final target = FlutterChatHistoryProvider(
        store,
        conversationId: 'c1',
        sessionIdResolver: () => sessionId,
      );

      await invoke(
        target,
        request: [ChatMessage.fromText(ChatRole.user, 'one')],
        response: [ChatMessage.fromText(ChatRole.assistant, 'a1')],
      );
      sessionId = 's2';
      await invoke(
        target,
        request: [ChatMessage.fromText(ChatRole.user, 'two')],
        response: [ChatMessage.fromText(ChatRole.assistant, 'a2')],
      );
      final history = (await target.provideChatHistory(
        InvokingContext(agent, session, const []),
      )).toList();

      expect(history.map((m) => m.text), ['one', 'a1', 'two', 'a2']);
      final records = await store.query(ChatMessageRecords.collection);
      final sessions = {
        for (final record in records)
          record.value[ChatMessageRecords.seqField]:
              record.value[ChatMessageRecords.sessionIdField],
      };
      expect(sessions, {0: 's1', 1: 's1', 2: 's2', 3: 's2'});
    });

    test('conversations are isolated from each other', () async {
      await invoke(
        provider(conversationId: 'c1'),
        request: [ChatMessage.fromText(ChatRole.user, 'mine')],
        response: const [],
      );
      await invoke(
        provider(conversationId: 'c2'),
        request: [ChatMessage.fromText(ChatRole.user, 'other')],
        response: const [],
      );

      final history = (await provider(
        conversationId: 'c1',
      ).provideChatHistory(InvokingContext(agent, session, const []))).toList();

      expect(history.map((m) => m.text), ['mine']);
    });

    test('stamps senderAgentId on non-user messages only', () async {
      await invoke(
        provider(senderAgentId: 'agent-7'),
        request: [ChatMessage.fromText(ChatRole.user, 'q')],
        response: [ChatMessage.fromText(ChatRole.assistant, 'a')],
      );

      final records = await store.query(
        ChatMessageRecords.collection,
        query: const RecordQuery(orderBy: ChatMessageRecords.seqField),
      );

      expect(records[0].value[ChatMessageRecords.senderAgentIdField], isNull);
      expect(
        records[1].value[ChatMessageRecords.senderAgentIdField],
        'agent-7',
      );
    });

    test('does not re-store provided history on the next turn', () async {
      final target = provider();
      await invoke(
        target,
        request: [ChatMessage.fromText(ChatRole.user, 'one')],
        response: [ChatMessage.fromText(ChatRole.assistant, 'a1')],
      );

      // Simulate the next turn: history is provided (stamped) and merged
      // with the new request, then the merged list comes back to invoked.
      final merged = (await target.invoking(
        InvokingContext(agent, session, [
          ChatMessage.fromText(ChatRole.user, 'two'),
        ]),
      )).toList();
      await invoke(
        target,
        request: merged,
        response: [ChatMessage.fromText(ChatRole.assistant, 'a2')],
      );

      final history = (await target.provideChatHistory(
        InvokingContext(agent, session, const []),
      )).toList();
      expect(history.map((m) => m.text), ['one', 'a1', 'two', 'a2']);
    });

    test('invoking prepends stamped history to the request', () async {
      final target = provider();
      await invoke(
        target,
        request: [ChatMessage.fromText(ChatRole.user, 'earlier')],
        response: [ChatMessage.fromText(ChatRole.assistant, 'reply')],
      );

      final merged = (await target.invoking(
        InvokingContext(agent, session, [
          ChatMessage.fromText(ChatRole.user, 'now'),
        ]),
      )).toList();

      expect(merged.map((m) => m.text), ['earlier', 'reply', 'now']);
      expect(
        merged[0].getAgentRequestMessageSourceType(),
        AgentRequestMessageSourceType.chatHistory,
      );
      expect(
        merged[2].getAgentRequestMessageSourceType(),
        isNot(AgentRequestMessageSourceType.chatHistory),
      );
    });

    test('skips storage when the invocation failed', () async {
      final target = provider();

      await target.invoked(
        InvokedContext(agent, session, [
          ChatMessage.fromText(ChatRole.user, 'q'),
        ], invokeException: Exception('boom')),
      );

      expect(await store.query(ChatMessageRecords.collection), isEmpty);
    });
  });
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

class _TestAgent extends AIAgent {
  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => <String, Object?>{};

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async =>
      AgentResponse(message: ChatMessage.fromText(ChatRole.assistant, 'ok'));

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {}
}
