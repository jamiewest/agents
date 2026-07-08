import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redactStaleToolResults', () {
    test('replaces volatile results and keeps other tools intact', () {
      final messages = [
        ChatMessage(
          role: ChatRole.assistant,
          contents: [
            FunctionCallContent(callId: 'c1', name: 'get_current_time'),
            FunctionCallContent(callId: 'c2', name: 'lookup'),
          ],
        ),
        ChatMessage(
          role: ChatRole.tool,
          contents: [
            FunctionResultContent(
              callId: 'c1',
              result: {'localDateTime': '3:04 PM'},
            ),
            FunctionResultContent(callId: 'c2', result: 'stable'),
          ],
        ),
      ];

      redactStaleToolResults(messages, {'get_current_time'});

      final results = messages[1].contents
          .whereType<FunctionResultContent>()
          .toList();
      final redacted = results[0].result! as Map<String, Object?>;
      expect(redacted['stale'], true);
      expect(redacted['note'], contains('get_current_time'));
      expect(results[0].callId, 'c1');
      expect(results[1].result, 'stable');
      // The call itself stays; only the payload is replaced.
      expect(
        messages[0].contents.whereType<FunctionCallContent>(),
        hasLength(2),
      );
    });

    test('matches on the result-recorded tool name without a call', () {
      final messages = [
        ChatMessage(
          role: ChatRole.tool,
          contents: [
            FunctionResultContent(
              callId: 'orphan',
              name: 'get_current_time',
              result: {'localDateTime': '3:04 PM'},
            ),
          ],
        ),
      ];

      redactStaleToolResults(messages, {'get_current_time'});

      final result = messages[0].contents
          .whereType<FunctionResultContent>()
          .single;
      expect((result.result! as Map<String, Object?>)['stale'], true);
      expect(result.name, 'get_current_time');
    });

    test('is a no-op for an empty volatile set', () {
      final original = {'localDateTime': '3:04 PM'};
      final messages = [
        ChatMessage(
          role: ChatRole.tool,
          contents: [
            FunctionResultContent(
              callId: 'c1',
              name: 'get_current_time',
              result: original,
            ),
          ],
        ),
      ];

      redactStaleToolResults(messages, const {});

      expect(
        messages[0].contents.whereType<FunctionResultContent>().single.result,
        same(original),
      );
    });
  });

  group('FlutterChatHistoryProvider stale-result redaction', () {
    test('provides redacted history while storing real values', () async {
      final store = InMemoryRecordStore();
      final agent = _TestAgent();
      final session = _TestSession();
      final provider = FlutterChatHistoryProvider(
        store,
        conversationId: 'c1',
        sessionIdResolver: () => 's1',
        staleToolResultNames: const {currentTimeToolName},
      );

      await provider.invoked(
        InvokedContext(
          agent,
          session,
          [ChatMessage.fromText(ChatRole.user, 'what time is it?')],
          responseMessages: [
            ChatMessage(
              role: ChatRole.assistant,
              contents: [
                FunctionCallContent(callId: 'c1', name: currentTimeToolName),
              ],
            ),
            ChatMessage(
              role: ChatRole.tool,
              contents: [
                FunctionResultContent(
                  callId: 'c1',
                  result: {'localDateTime': '3:04 PM'},
                ),
              ],
            ),
            ChatMessage.fromText(ChatRole.assistant, 'It is 3:04 PM.'),
          ],
        ),
      );

      final history = (await provider.provideChatHistory(
        InvokingContext(agent, session, const []),
      )).toList();

      final result = [
        for (final message in history)
          ...message.contents.whereType<FunctionResultContent>(),
      ].single;
      expect((result.result! as Map<String, Object?>)['stale'], true);

      // The durable transcript keeps the genuine value.
      final records = await store.query(ChatMessageRecords.collection);
      final storedResults = records
          .map((r) => r.value[ChatMessageRecords.messageField].toString())
          .where((s) => s.contains('3:04 PM'));
      expect(storedResults, isNotEmpty);
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
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? jsonSerializerOptions,
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
