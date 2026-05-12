import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/delegating_ai_agent.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('DelegatingAIAgent', () {
    test('constructor_WithValidInnerAgent_SetsInnerAgent', () {
      final inner = _TestAgent();
      final delegating = _TestDelegatingAgent(inner);

      expect(delegating.innerAgent, same(inner));
    });

    test('name_DelegatesToInnerAgent', () {
      final inner = _TestAgent(nameValue: 'InnerName');
      final delegating = _TestDelegatingAgent(inner);

      expect(delegating.name, 'InnerName');
    });

    test('description_DelegatesToInnerAgent', () {
      final inner = _TestAgent(descriptionValue: 'Inner desc');
      final delegating = _TestDelegatingAgent(inner);

      expect(delegating.description, 'Inner desc');
    });

    test('createSessionAsync_DelegatesToInnerAgentAsync', () async {
      final inner = _TestAgent();
      final delegating = _TestDelegatingAgent(inner);

      final session = await delegating.createSession();

      expect(session, isA<_TestSession>());
    });

    test('deserializeSessionAsync_DelegatesToInnerAgentAsync', () async {
      final inner = _TestAgent();
      final delegating = _TestDelegatingAgent(inner);

      final session = await delegating.deserializeSession('{}');

      expect(session, isA<_TestSession>());
    });

    test('runAsyncDefaultsToInnerAgentAsync', () async {
      final inner = _TestAgent(responseText: 'from inner');
      final delegating = _TestDelegatingAgent(inner);

      final response = await delegating.run(null, null);

      expect(response.text, 'from inner');
    });

    test('runStreamingAsyncDefaultsToInnerAgentAsync', () async {
      final inner = _TestAgent(responseText: 'streamed');
      final delegating = _TestDelegatingAgent(inner);

      final updates = await delegating.runStreaming(null, null).toList();

      expect(updates, isNotEmpty);
      expect(updates.first.text, 'streamed');
    });

    test(
      'getServiceReturnsSelfIfCompatibleWithRequestAndKeyIsNull',
      () {
        final inner = _TestAgent();
        final delegating = _TestDelegatingAgent(inner);

        final service = delegating.getService(_TestDelegatingAgent);

        expect(service, same(delegating));
      },
    );

    test('getServiceDelegatesToInnerIfKeyIsNotNull', () {
      final inner = _TestAgent();
      final delegating = _TestDelegatingAgent(inner);

      final service = delegating.getService(
        _TestAgent,
        serviceKey: 'key',
      );

      expect(service, isNot(same(delegating)));
    });

    test('getServiceDelegatesToInnerIfNotCompatibleWithRequest', () {
      final inner = _TestAgent();
      final delegating = _TestDelegatingAgent(inner);

      final service = delegating.getService(AIAgent);

      expect(service, same(inner));
    });

    test('id_IsOwnNotDelegated', () {
      final inner = _TestAgent();
      final delegating = _TestDelegatingAgent(inner);

      expect(delegating.id == inner.id, isFalse);
    });
  });
}

class _TestAgent extends AIAgent {
  _TestAgent({
    this.responseText = 'response',
    this.nameValue,
    this.descriptionValue,
  });

  final String responseText;
  final String? nameValue;
  final String? descriptionValue;

  @override
  String? get name => nameValue;

  @override
  String? get description => descriptionValue;

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

class _TestDelegatingAgent extends DelegatingAIAgent {
  _TestDelegatingAgent(super.innerAgent);
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}
