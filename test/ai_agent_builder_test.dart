// ignore_for_file: non_constant_identifier_names
import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/ai/ai_agent_builder.dart';
import 'package:agents/src/ai/anonymous_delegating_ai_agent.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('AIAgentBuilder', () {
    test('build_WithNoMiddleware_ReturnsInnerAgent', () {
      final inner = _TestAgent();
      final builder = AIAgentBuilder(innerAgent: inner);

      final agent = builder.build();

      expect(agent, same(inner));
    });

    test('build_WithFactory_ReturnsAgentFromFactory', () {
      final inner = _TestAgent();
      final builder = AIAgentBuilder(innerAgentFactory: (_) => inner);

      final agent = builder.build();

      expect(agent, same(inner));
    });

    test('use_WithSimpleFactory_AppliesMiddleware', () {
      final inner = _TestAgent();
      final wrapper = _TestAgent();
      final builder = AIAgentBuilder(innerAgent: inner)
          .use(agentFactory: (_) => wrapper);

      final agent = builder.build();

      expect(agent, same(wrapper));
    });

    test('use_WithMultipleMiddleware_AppliesInCorrectOrder', () async {
      final log = <String>[];
      final inner = _TestAgent(responseText: 'inner');

      final builder = AIAgentBuilder(innerAgent: inner)
          .use(
            runFunc: (msgs, session, opts, innerAgent, ct) async {
              log.add('first');
              return innerAgent.runCore(msgs,
                  session: session, options: opts, cancellationToken: ct);
            },
          )
          .use(
            runFunc: (msgs, session, opts, innerAgent, ct) async {
              log.add('second');
              return innerAgent.runCore(msgs,
                  session: session, options: opts, cancellationToken: ct);
            },
          );

      final agent = builder.build();
      await agent.run(null, null);

      expect(log, ['first', 'second']);
    });

    test('use_WithBothDelegatesNull_ThrowsArgumentNullException', () {
      final inner = _TestAgent();
      final builder = AIAgentBuilder(innerAgent: inner);

      expect(() => builder.use().build(), throwsA(isA<ArgumentError>()));
    });

    test('use_WithSharedDelegate_CreatesAnonymousDelegatingAgent', () {
      final inner = _TestAgent();
      final builder = AIAgentBuilder(innerAgent: inner).use(
        sharedFunc: (msgs, session, opts, invoker, ct) =>
            invoker(msgs, session, opts, ct),
        runFunc: (msgs, session, opts, innerAgent, ct) =>
            innerAgent.runCore(msgs),
      );

      final agent = builder.build();

      expect(agent, isA<AnonymousDelegatingAIAgent>());
    });

    test('use_WithRunFuncOnly_CreatesAnonymousDelegatingAgent', () {
      final inner = _TestAgent();
      final builder = AIAgentBuilder(innerAgent: inner).use(
        runFunc: (msgs, session, opts, innerAgent, ct) =>
            innerAgent.runCore(msgs,
                session: session, options: opts, cancellationToken: ct),
      );

      final agent = builder.build();

      expect(agent, isA<AnonymousDelegatingAIAgent>());
    });

    test('use_WithStreamingFuncOnly_CreatesAnonymousDelegatingAgent', () {
      final inner = _TestAgent();
      final builder = AIAgentBuilder(innerAgent: inner).use(
        runStreamingFunc: (msgs, session, opts, innerAgent, ct) =>
            innerAgent.runCoreStreaming(msgs,
                session: session, options: opts, cancellationToken: ct),
      );

      final agent = builder.build();

      expect(agent, isA<AnonymousDelegatingAIAgent>());
    });

    test('use_WithBothDelegates_CreatesAnonymousDelegatingAgent', () {
      final inner = _TestAgent();
      final builder = AIAgentBuilder(innerAgent: inner).use(
        runFunc: (msgs, session, opts, innerAgent, ct) =>
            innerAgent.runCore(msgs,
                session: session, options: opts, cancellationToken: ct),
        runStreamingFunc: (msgs, session, opts, innerAgent, ct) =>
            innerAgent.runCoreStreaming(msgs,
                session: session, options: opts, cancellationToken: ct),
      );

      final agent = builder.build();

      expect(agent, isA<AnonymousDelegatingAIAgent>());
    });
  });
}

class _TestAgent extends AIAgent {
  _TestAgent({this.responseText = 'response'});

  final String responseText;

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
    dynamic serializedState, {
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
  }) async {
    return AgentResponse(
      message: ChatMessage.fromText(ChatRole.assistant, responseText),
    );
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    yield AgentResponseUpdate(
      role: ChatRole.assistant,
      content: responseText,
    );
  }
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}
