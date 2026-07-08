// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart' show ChatClientAgent;
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UsageTrackingChatClient streaming', () {
    test(
      'records last-wins usage from updates and injects UsageContent',
      () async {
        // Arrange: provider reports cumulative usage across two updates, the
        // way Anthropic reconciles start + delta events.
        final sink = _RecordingSink();
        final client = _tracking(
          _ScriptedChatClient([
            [
              ChatResponseUpdate(
                role: ChatRole.assistant,
                messageId: 'm1',
                contents: [TextContent('hel')],
                usage: UsageDetails(inputTokenCount: 10, outputTokenCount: 1),
              ),
              ChatResponseUpdate(
                role: ChatRole.assistant,
                messageId: 'm1',
                contents: [TextContent('lo')],
                usage: UsageDetails(
                  inputTokenCount: 10,
                  outputTokenCount: 5,
                  totalTokenCount: 15,
                ),
              ),
            ],
          ]),
          sink,
        );

        // Act
        final updates = await client
            .getStreamingResponse(messages: _ask())
            .toList();

        // Assert: one record, matching the final (not summed) usage.
        expect(sink.records, hasLength(1));
        final record = sink.records.single;
        expect(record.inputTokenCount, 10);
        expect(record.outputTokenCount, 5);
        expect(record.totalTokenCount, 15);
        expect(record.modelId, 'test-model');
        expect(record.sourceId, 'source-1');
        expect(record.provider, 'testProvider');
        expect(record.conversationId, 'conv-1');
        expect(record.sessionId, 'session-1');

        final usageContents = [
          for (final u in updates) ...u.contents.whereType<UsageContent>(),
        ];
        expect(usageContents, hasLength(1));
        expect(usageContents.single.details.inputTokenCount, 10);
        expect(usageContents.single.details.outputTokenCount, 5);
        expect(updates.last.messageId, 'm1');
      },
    );

    test(
      'falls back to provider UsageContent without double counting',
      () async {
        final sink = _RecordingSink();
        final client = _tracking(
          _ScriptedChatClient([
            [
              ChatResponseUpdate(
                role: ChatRole.assistant,
                messageId: 'm1',
                contents: [
                  TextContent('hi'),
                  UsageContent(
                    UsageDetails(inputTokenCount: 7, outputTokenCount: 3),
                  ),
                ],
              ),
            ],
          ]),
          sink,
        );

        final updates = await client
            .getStreamingResponse(messages: _ask())
            .toList();

        expect(sink.records, hasLength(1));
        expect(sink.records.single.inputTokenCount, 7);
        expect(sink.records.single.outputTokenCount, 3);
        // No synthetic update was appended: the provider's own content is the
        // only UsageContent in the stream.
        final usageContents = [
          for (final u in updates) ...u.contents.whereType<UsageContent>(),
        ];
        expect(usageContents, hasLength(1));
      },
    );

    test('reports nothing when the provider gives no usage', () async {
      final sink = _RecordingSink();
      final client = _tracking(
        _ScriptedChatClient([
          [
            ChatResponseUpdate(
              role: ChatRole.assistant,
              messageId: 'm1',
              contents: [TextContent('hi')],
            ),
          ],
        ]),
        sink,
      );

      final updates = await client
          .getStreamingResponse(messages: _ask())
          .toList();

      expect(sink.records, isEmpty);
      expect(
        updates.any((u) => u.contents.any((c) => c is UsageContent)),
        isFalse,
      );
    });
  });

  group('UsageTrackingChatClient input stripping', () {
    test('removes UsageContent from replayed history without mutating '
        'the transcript', () async {
      // Arrange: a prior assistant turn carries the UsageContent this
      // decorator injected when it was persisted.
      final priorTurn = ChatMessage(
        role: ChatRole.assistant,
        contents: [
          TextContent('earlier answer'),
          UsageContent(UsageDetails(inputTokenCount: 4, outputTokenCount: 2)),
        ],
      );
      final history = [
        ChatMessage.fromText(ChatRole.user, 'hi'),
        priorTurn,
        ChatMessage.fromText(ChatRole.user, 'again'),
      ];
      final inner = _InputCapturingChatClient();
      final client = _tracking(inner, _RecordingSink());

      // Act: exercise both call paths against the same history.
      await client.getResponse(messages: history);
      await client.getStreamingResponse(messages: history).drain<void>();

      // Assert: the provider never sees UsageContent as input...
      for (final sent in inner.calls) {
        expect(
          sent.any((m) => m.contents.any((c) => c is UsageContent)),
          isFalse,
        );
        expect(sent[1].text, 'earlier answer');
      }
      // ...while the persisted transcript keeps its usage detail.
      expect(priorTurn.contents.whereType<UsageContent>(), hasLength(1));
    });
  });

  group('UsageTrackingChatClient getResponse', () {
    test('records response usage and attaches UsageContent', () async {
      final sink = _RecordingSink();
      final client = _tracking(
        _ScriptedChatClient.nonStreaming(
          ChatResponse.fromMessage(
              ChatMessage.fromText(ChatRole.assistant, 'hi'),
            )
            ..usage = UsageDetails(
              inputTokenCount: 4,
              outputTokenCount: 2,
              totalTokenCount: 6,
            ),
        ),
        sink,
      );

      final response = await client.getResponse(messages: _ask());

      expect(sink.records.single.totalTokenCount, 6);
      final usage = response.messages.last.contents
          .whereType<UsageContent>()
          .single;
      expect(usage.details.inputTokenCount, 4);
      expect(usage.details.outputTokenCount, 2);
    });

    test('works without a scope', () async {
      final sink = _RecordingSink();
      final client = UsageTrackingChatClient(
        _ScriptedChatClient.nonStreaming(
          ChatResponse.fromMessage(
            ChatMessage.fromText(ChatRole.assistant, 'hi'),
          )..usage = UsageDetails(inputTokenCount: 1, outputTokenCount: 1),
        ),
        sink: sink,
        modelId: 'test-model',
        sourceId: 'source-1',
        provider: 'testProvider',
      );

      await client.getResponse(messages: _ask());

      expect(sink.records.single.conversationId, isNull);
      expect(sink.records.single.sessionId, isNull);
    });
  });

  group('UsageContent propagation through the agent tool loop', () {
    test('survives ChatClientAgent streaming with tool invocation', () async {
      // Arrange: first model call requests a tool, second answers. Each
      // call reports usage on its updates. The agent's default middleware
      // includes the function-invoking loop, so this exercises the same
      // pipeline the app runs.
      final sink = _RecordingSink();
      final inner = _ScriptedChatClient([
        [
          ChatResponseUpdate(
            role: ChatRole.assistant,
            messageId: 'm1',
            contents: [
              FunctionCallContent(
                callId: 'call-1',
                name: 'lookup',
                arguments: const {},
              ),
            ],
            finishReason: ChatFinishReason.toolCalls,
            usage: UsageDetails(inputTokenCount: 10, outputTokenCount: 2),
          ),
        ],
        [
          ChatResponseUpdate(
            role: ChatRole.assistant,
            messageId: 'm2',
            contents: [TextContent('done')],
            finishReason: ChatFinishReason.stop,
            usage: UsageDetails(inputTokenCount: 20, outputTokenCount: 4),
          ),
        ],
      ]);
      final tool = AIFunctionFactory.create(
        name: 'lookup',
        callback: (_, {cancellationToken}) async => 'result',
      );
      final agent = ChatClientAgent.withSettings(
        _tracking(inner, sink),
        tools: [tool],
      );

      // Act: stream a run and collect the agent-level updates the UI sees.
      final updates = await agent
          .runStreaming(null, null, message: 'hi')
          .toList();

      // Assert: both model calls were recorded in the ledger.
      expect(sink.records, hasLength(2));
      expect(sink.records[0].inputTokenCount, 10);
      expect(sink.records[1].inputTokenCount, 20);

      // The injected UsageContent reaches AgentResponseUpdate.contents —
      // this is what the live UI aggregates per turn.
      final usageContents = [
        for (final update in updates)
          ...update.contents.whereType<UsageContent>(),
      ];
      expect(usageContents, hasLength(2));
      expect(
        usageContents.map((u) => u.details.inputTokenCount),
        containsAll([10, 20]),
      );
    });

    test('survives ChatClientAgent non-streaming run into messages', () async {
      final sink = _RecordingSink();
      final inner = _ScriptedChatClient.nonStreaming(
        ChatResponse.fromMessage(
          ChatMessage.fromText(ChatRole.assistant, 'done'),
        )..usage = UsageDetails(inputTokenCount: 8, outputTokenCount: 3),
      );
      final agent = ChatClientAgent.withSettings(
        _tracking(inner, sink),
        tools: [],
      );

      final response = await agent.run(null, null, message: 'hi');

      expect(sink.records, hasLength(1));
      final usage = [
        for (final message in response.messages)
          ...message.contents.whereType<UsageContent>(),
      ];
      expect(usage, hasLength(1));
      expect(usage.single.details.inputTokenCount, 8);
      expect(usage.single.details.outputTokenCount, 3);
    });
  });
}

Iterable<ChatMessage> _ask() => [ChatMessage.fromText(ChatRole.user, 'hi')];

UsageTrackingChatClient _tracking(ChatClient inner, UsageRecordSink sink) =>
    UsageTrackingChatClient(
      inner,
      sink: sink,
      modelId: 'test-model',
      sourceId: 'source-1',
      provider: 'testProvider',
      scope: AgentScope(
        conversationId: 'conv-1',
        sessionIdResolver: () => 'session-1',
      ),
    );

final class _RecordingSink implements UsageRecordSink {
  final List<ChatUsageRecord> records = [];

  @override
  void record(ChatUsageRecord record) => records.add(record);
}

/// A fake client that captures the messages each call sends downstream.
final class _InputCapturingChatClient implements ChatClient {
  final List<List<ChatMessage>> calls = [];

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    calls.add(messages.toList());
    return ChatResponse.fromMessage(
      ChatMessage.fromText(ChatRole.assistant, 'ok'),
    );
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) {
    calls.add(messages.toList());
    return Stream.fromIterable([
      ChatResponseUpdate(
        role: ChatRole.assistant,
        messageId: 'm1',
        contents: [TextContent('ok')],
      ),
    ]);
  }

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}
}

/// A fake client that replays scripted update lists, one per call.
final class _ScriptedChatClient implements ChatClient {
  _ScriptedChatClient(this._scripts) : _response = null;

  _ScriptedChatClient.nonStreaming(ChatResponse response)
    : _scripts = const [],
      _response = response;

  final List<List<ChatResponseUpdate>> _scripts;
  final ChatResponse? _response;
  int _call = 0;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async => _response!;

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) {
    final script = _scripts[_call++];
    return Stream.fromIterable(script);
  }

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}
}
