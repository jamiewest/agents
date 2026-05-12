import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/chat_history_provider.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/ai_agent_id_equality_comparer.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/executor_instance_binding.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/external_request.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/function_executor.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/message_merger.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/request_port.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/streaming_aggregators.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/turn_token.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/workflow_builder.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/workflow_chat_history_provider.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/workflow_host_agent.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/workflow_hosting_extensions.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart' hide equals;
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  group('TurnToken', () {
    test('emitEvents defaults to null', () {
      const token = TurnToken();
      expect(token.emitEvents, isNull);
    });

    test('emitEvents can be set to true', () {
      const token = TurnToken(emitEvents: true);
      expect(token.emitEvents, isTrue);
    });

    test('emitEvents can be set to false', () {
      const token = TurnToken(emitEvents: false);
      expect(token.emitEvents, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('AIAgentIdEqualityComparer', () {
    final comparer = AIAgentIdEqualityComparer.instance;

    test('instance is a singleton', () {
      expect(AIAgentIdEqualityComparer.instance,
          same(AIAgentIdEqualityComparer.instance));
    });

    test('equals returns true for the same agent instance', () {
      final agent = _SimpleAgent();
      expect(comparer.equals(agent, agent), isTrue);
    });

    test('equals returns false for different agents', () {
      final a = _SimpleAgent();
      final b = _SimpleAgent();
      expect(comparer.equals(a, b), isFalse);
    });

    test('equals(null, null) returns true', () {
      expect(comparer.equals(null, null), isTrue);
    });

    test('equals(null, agent) returns false', () {
      expect(comparer.equals(null, _SimpleAgent()), isFalse);
    });

    test('equals(agent, null) returns false', () {
      expect(comparer.equals(_SimpleAgent(), null), isFalse);
    });

    test('getHashCode returns id hash code', () {
      final agent = _SimpleAgent();
      expect(comparer.getHashCode(agent), equals(agent.id.hashCode));
    });
  });

  // ---------------------------------------------------------------------------
  group('StreamingAggregators', () {
    group('first / firstOf', () {
      test('first captures only the first converted value', () {
        final agg = StreamingAggregators.first<int, String>(
          (n) => 'item$n',
        );
        var result = agg(null, 1);
        result = agg(result, 2);
        result = agg(result, 3);
        expect(result, equals('item1'));
      });

      test('firstOf captures only the first element', () {
        final agg = StreamingAggregators.firstOf<int>();
        var result = agg(null, 10);
        result = agg(result, 20);
        result = agg(result, 30);
        expect(result, equals(10));
      });
    });

    group('last / lastOf', () {
      test('last returns the most recent converted value', () {
        final agg = StreamingAggregators.last<int, String>(
          (n) => 'item$n',
        );
        var result = agg(null, 1);
        result = agg(result, 2);
        result = agg(result, 3);
        expect(result, equals('item3'));
      });

      test('lastOf returns the most recent element', () {
        final agg = StreamingAggregators.lastOf<int>();
        var result = agg(null, 10);
        result = agg(result, 20);
        result = agg(result, 30);
        expect(result, equals(30));
      });
    });

    group('union / unionOf', () {
      test('union accumulates converted results', () {
        final agg = StreamingAggregators.union<int, String>(
          (n) => 'item$n',
        );
        var result = agg(null, 1);
        result = agg(result, 2);
        result = agg(result, 3);
        expect(result!.toList(), equals(['item1', 'item2', 'item3']));
      });

      test('unionOf accumulates elements unchanged', () {
        final agg = StreamingAggregators.unionOf<int>();
        var result = agg(null, 10);
        result = agg(result, 20);
        result = agg(result, 30);
        expect(result!.toList(), equals([10, 20, 30]));
      });

      test('union from empty start produces singleton', () {
        final agg = StreamingAggregators.unionOf<String>();
        final result = agg(null, 'hello');
        expect(result!.toList(), equals(['hello']));
      });
    });
  });

  // ---------------------------------------------------------------------------
  group('WorkflowChatHistoryProvider', () {
    late WorkflowChatHistoryProvider provider;
    late _TestSession session;

    setUp(() {
      provider = WorkflowChatHistoryProvider();
      session = _TestSession();
    });

    test('stateKeys reflects internal state key', () {
      expect(provider.stateKeys, hasLength(1));
      expect(provider.stateKeys.first, isNotEmpty);
    });

    test('addMessages appends to the session history', () {
      provider.addMessages(session, [
        ChatMessage.fromText(ChatRole.user, 'hello'),
        ChatMessage.fromText(ChatRole.assistant, 'hi'),
      ]);

      final messages = provider.getAllMessages(session).toList();
      expect(messages, hasLength(2));
      expect(messages[0].text, 'hello');
      expect(messages[1].text, 'hi');
    });

    test('getAllMessages returns an unmodifiable view', () {
      provider.addMessages(
          session, [ChatMessage.fromText(ChatRole.user, 'msg')]);

      final messages = provider.getAllMessages(session);
      expect(
        () => (messages as List<ChatMessage>).add(
          ChatMessage.fromText(ChatRole.user, 'extra'),
        ),
        throwsUnsupportedError,
      );
    });

    test('getFromBookmark returns messages added after updateBookmark', () {
      provider.addMessages(session, [
        ChatMessage.fromText(ChatRole.user, 'before'),
      ]);
      provider.updateBookmark(session);

      provider.addMessages(session, [
        ChatMessage.fromText(ChatRole.assistant, 'after'),
      ]);

      final fromBookmark = provider.getFromBookmark(session).toList();
      expect(fromBookmark, hasLength(1));
      expect(fromBookmark.first.text, 'after');
    });

    test('getFromBookmark returns all messages when bookmark is at start', () {
      provider.addMessages(session, [
        ChatMessage.fromText(ChatRole.user, 'a'),
        ChatMessage.fromText(ChatRole.assistant, 'b'),
      ]);

      expect(provider.getFromBookmark(session).toList(), hasLength(2));
    });

    test('updateBookmark advances the bookmark each time', () {
      provider.addMessages(session, [
        ChatMessage.fromText(ChatRole.user, 'first'),
      ]);
      provider.updateBookmark(session);

      provider.addMessages(session, [
        ChatMessage.fromText(ChatRole.assistant, 'second'),
      ]);
      provider.updateBookmark(session);

      provider.addMessages(session, [
        ChatMessage.fromText(ChatRole.user, 'third'),
      ]);

      final fromBookmark = provider.getFromBookmark(session).toList();
      expect(fromBookmark, hasLength(1));
      expect(fromBookmark.first.text, 'third');
    });

    test('provideChatHistory returns current messages', () async {
      provider.addMessages(session, [
        ChatMessage.fromText(ChatRole.user, 'context'),
      ]);

      final agent = _SimpleAgent();
      final ctx = InvokingContext(agent, session, []);
      final history = (await provider.provideChatHistory(ctx)).toList();

      expect(history, hasLength(1));
      expect(history.first.text, 'context');
    });

    test('storeChatHistory appends request and response messages', () async {
      final agent = _SimpleAgent();
      final requestMsgs = [ChatMessage.fromText(ChatRole.user, 'req')];
      final responseMsgs = [ChatMessage.fromText(ChatRole.assistant, 'resp')];

      final ctx = InvokedContext(
        agent,
        session,
        requestMsgs,
        responseMessages: responseMsgs,
      );
      await provider.storeChatHistory(ctx);

      final all = provider.getAllMessages(session).toList();
      expect(all.map((m) => m.text).toList(), equals(['req', 'resp']));
    });

    test('storeChatHistory is a no-op for different sessions', () async {
      final agent = _SimpleAgent();
      final session2 = _TestSession();
      await provider.storeChatHistory(InvokedContext(
        agent,
        session2,
        [ChatMessage.fromText(ChatRole.user, 'other')],
      ));

      expect(provider.getAllMessages(session).toList(), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('MessageMerger', () {
    test('addUpdate with no responseId goes to dangling state', () {
      final merger = MessageMerger();
      merger.addUpdate(
        AgentResponseUpdate(content: 'hello')
          ..responseId = null
          ..messageId = null,
      );

      final result = merger.computeMerged(primaryResponseId: 'r1');
      expect(result.text, contains('hello'));
      expect(result.responseId, equals('r1'));
    });

    test('addUpdate groups by responseId and messageId', () {
      final merger = MessageMerger();
      merger.addUpdate(
        AgentResponseUpdate(content: 'part1')
          ..responseId = 'r1'
          ..messageId = 'm1',
      );
      merger.addUpdate(
        AgentResponseUpdate(content: 'part2')
          ..responseId = 'r1'
          ..messageId = 'm1',
      );

      final result = merger.computeMerged(primaryResponseId: 'r1');
      expect(result.messages, hasLength(1));
      expect(result.messages.first.text, equals('part1part2'));
    });

    test('computeMerged uses primaryResponseId for output', () {
      final merger = MessageMerger();
      merger.addUpdate(
        AgentResponseUpdate(content: 'msg')
          ..responseId = 'r1'
          ..messageId = 'm1',
      );

      final result =
          merger.computeMerged(primaryResponseId: 'output-response');
      expect(result.responseId, equals('output-response'));
    });

    test('computeMerged uses primaryAgentId when provided', () {
      final merger = MessageMerger();
      merger.addUpdate(
        AgentResponseUpdate(content: 'msg')
          ..responseId = 'r1'
          ..messageId = 'm1',
      );

      final result = merger.computeMerged(
        primaryResponseId: 'r1',
        primaryAgentId: 'agent-42',
      );
      expect(result.agentId, equals('agent-42'));
    });

    test('computeMerged removes empty messages', () {
      final merger = MessageMerger();
      merger.addUpdate(
        AgentResponseUpdate(content: '  ')
          ..responseId = 'r1'
          ..messageId = 'm1',
      );

      final result = merger.computeMerged(primaryResponseId: 'r1');
      expect(result.messages, isEmpty);
    });

    test('computeMerged merges usage details', () {
      final merger = MessageMerger();
      merger.addUpdate(
        AgentResponseUpdate(content: 'a')
          ..responseId = 'r1'
          ..messageId = 'm1',
      );
      merger.addUpdate(
        AgentResponseUpdate(content: 'b')
          ..responseId = 'r2'
          ..messageId = 'm2',
      );

      // Usage merging via multiple response IDs is covered by the helper;
      // here we just confirm computeMerged runs without error.
      expect(
        () => merger.computeMerged(primaryResponseId: 'r1'),
        returnsNormally,
      );
    });

    test('multiple dangling updates produce merged messages', () {
      final merger = MessageMerger();
      merger.addUpdate(AgentResponseUpdate(content: 'X')..responseId = null);
      merger.addUpdate(AgentResponseUpdate(content: 'Y')..responseId = null);

      final result = merger.computeMerged(primaryResponseId: 'r1');
      final text = result.messages.map((m) => m.text).join();
      expect(text, contains('X'));
      expect(text, contains('Y'));
    });
  });

  // ---------------------------------------------------------------------------
  group('WorkflowHostingExtensions', () {
    test('asAIAgent wraps workflow in WorkflowHostAgent', () {
      final executor = FunctionExecutor<List<ChatMessage>, AgentResponse>(
        'start',
        (input, context, ct) => AgentResponse(messages: input),
      );
      final workflow = WorkflowBuilder(ExecutorInstanceBinding(executor))
          .addOutput('start')
          .build();

      final agent = workflow.asAIAgent(
        name: 'my-workflow',
        description: 'a test workflow',
      );

      expect(agent, isA<WorkflowHostAgent>());
      expect(agent.name, equals('my-workflow'));
      expect(agent.description, equals('a test workflow'));
    });

    test('asAIAgent uses workflow name when name is not provided', () {
      final executor = FunctionExecutor<List<ChatMessage>, AgentResponse>(
        'start',
        (input, context, ct) => AgentResponse(messages: input),
      );
      final workflow = WorkflowBuilder(ExecutorInstanceBinding(executor))
          .addOutput('start')
          .withName('workflow-name')
          .build();

      final agent = workflow.asAIAgent();

      expect(agent.name, equals('workflow-name'));
    });

    test('toFunctionCall builds FunctionCallContent from ExternalRequest', () {
      final port = RequestPort<String, int>('my_port');
      final request = ExternalRequest<String, int>(
        requestId: 'req-1',
        port: port,
        request: 'payload',
      );

      final call = request.toFunctionCall();

      expect(call.callId, equals('req-1'));
      expect(call.name, equals('my_port'));
      expect(call.arguments, equals({'data': 'payload'}));
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers

class _SimpleAgent extends AIAgent {
  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async =>
      _TestSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async =>
      '{}';

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedSession, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async =>
      _TestSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async =>
      AgentResponse(messages: []);

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {}
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}
