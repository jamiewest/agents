import 'package:a2a/a2a.dart' show A2AAgentExecutor;
import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/hosting/a2a/a2a_agent_handler.dart';
import 'package:agents/src/hosting/a2a/agent_run_mode.dart';
import 'package:agents/src/hosting/a2a/a2a_server_service_collection_extensions.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('A2AServerServiceCollectionExtensions', () {
    test('addA2AServer by name registers a keyed executor', () {
      final services = ServiceCollection()
        ..addKeyedSingleton<AIAgent>('myAgent', (_, _) => _StubAgent('myAgent'))
        ..addA2AServer(agentName: 'myAgent');
      final provider = services.buildServiceProvider();

      final executor = provider.getKeyedService<A2AAgentExecutor>('myAgent');

      expect(executor, isA<A2AAgentHandler>());
    });

    test('addA2AServer by agent instance registers under the agent name', () {
      final agent = _StubAgent('instanceAgent');
      final services = ServiceCollection()..addA2AServer(agent: agent);
      final provider = services.buildServiceProvider();

      final executor = provider.getKeyedService<A2AAgentExecutor>(
        'instanceAgent',
      );

      expect(executor, isA<A2AAgentHandler>());
    });

    test('configureOptions sets the run mode without throwing', () {
      final services = ServiceCollection()
        ..addKeyedSingleton<AIAgent>('myAgent', (_, _) => _StubAgent('myAgent'))
        ..addA2AServer(
          agentName: 'myAgent',
          configureOptions: (options) =>
              options.agentRunMode = AgentRunMode.allowBackgroundIfSupported,
        );
      final provider = services.buildServiceProvider();

      expect(
        provider.getKeyedService<A2AAgentExecutor>('myAgent'),
        isA<A2AAgentHandler>(),
      );
    });

    test('throws when neither agentName nor agent is supplied', () {
      expect(() => ServiceCollection().addA2AServer(), throwsArgumentError);
    });

    test('throws when both agentName and agent are supplied', () {
      expect(
        () => ServiceCollection().addA2AServer(
          agentName: 'x',
          agent: _StubAgent('x'),
        ),
        throwsArgumentError,
      );
    });

    test('throws when the agent instance has no name', () {
      expect(
        () => ServiceCollection().addA2AServer(agent: _StubAgent(null)),
        throwsArgumentError,
      );
    });
  });
}

class _StubAgent extends AIAgent {
  _StubAgent(this._name);

  final String? _name;

  @override
  String? get name => _name;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _StubSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions, // ignore: non_constant_identifier_names
    CancellationToken? cancellationToken,
  }) async => '{}';

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions, // ignore: non_constant_identifier_names
    CancellationToken? cancellationToken,
  }) async => _StubSession();

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
  }) async* {
    yield AgentResponseUpdate(role: ChatRole.assistant, content: 'ok');
  }
}

class _StubSession extends AgentSession {
  _StubSession() : super(AgentSessionStateBag(null));
}
