// ignore_for_file: non_constant_identifier_names
import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/hosting/ai_host_agent.dart';
import 'package:agents/src/hosting/local/in_memory_agent_session_store.dart';
import 'package:agents/src/hosting/noop_agent_session_store.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryAgentSessionStore', () {
    test('getSession creates a new session when none is saved', () async {
      final store = InMemoryAgentSessionStore();
      final agent = _TestAgent();

      final session = await store.getSession(agent, 'conv-1');

      expect(session, isA<_TestSession>());
    });

    test('saveSession then getSession round-trips the session', () async {
      final store = InMemoryAgentSessionStore();
      final agent = _TestAgent();
      final session = _TestSession(marker: 'saved-marker');

      await store.saveSession(agent, 'conv-1', session);
      final retrieved = await store.getSession(agent, 'conv-1') as _TestSession;

      expect(retrieved.marker, 'saved-marker');
    });

    test('different agents use separate stores for the same conversationId',
        () async {
      final store = InMemoryAgentSessionStore();
      final agentA = _TestAgent();
      final agentB = _TestAgent();
      final sessionA = _TestSession(marker: 'A');
      final sessionB = _TestSession(marker: 'B');

      await store.saveSession(agentA, 'conv-1', sessionA);
      await store.saveSession(agentB, 'conv-1', sessionB);

      final retrievedA = await store.getSession(agentA, 'conv-1') as _TestSession;
      final retrievedB = await store.getSession(agentB, 'conv-1') as _TestSession;

      expect(retrievedA.marker, 'A');
      expect(retrievedB.marker, 'B');
    });

    test('different conversationIds are stored independently', () async {
      final store = InMemoryAgentSessionStore();
      final agent = _TestAgent();
      final sessionA = _TestSession(marker: 'conv-A');
      final sessionB = _TestSession(marker: 'conv-B');

      await store.saveSession(agent, 'conv-A', sessionA);
      await store.saveSession(agent, 'conv-B', sessionB);

      final retA = await store.getSession(agent, 'conv-A') as _TestSession;
      final retB = await store.getSession(agent, 'conv-B') as _TestSession;

      expect(retA.marker, 'conv-A');
      expect(retB.marker, 'conv-B');
    });

    test('overwriting a session replaces the previous one', () async {
      final store = InMemoryAgentSessionStore();
      final agent = _TestAgent();

      await store.saveSession(agent, 'conv-1', _TestSession(marker: 'first'));
      await store.saveSession(agent, 'conv-1', _TestSession(marker: 'second'));
      final retrieved = await store.getSession(agent, 'conv-1') as _TestSession;

      expect(retrieved.marker, 'second');
    });
  });

  group('NoopAgentSessionStore', () {
    test('getSession always creates a new session', () async {
      final store = NoopAgentSessionStore();
      final agent = _TestAgent();

      final s1 = await store.getSession(agent, 'conv-1');
      final s2 = await store.getSession(agent, 'conv-1');

      expect(s1, isNot(same(s2)));
    });

    test('saveSession is a no-op that returns normally', () async {
      final store = NoopAgentSessionStore();
      final agent = _TestAgent();

      await expectLater(
        store.saveSession(agent, 'conv-1', _TestSession()),
        completes,
      );

      // getSession still creates a new session (nothing was persisted)
      final session = await store.getSession(agent, 'conv-1');
      expect(session, isA<_TestSession>());
    });
  });

  group('AIHostAgent', () {
    test('getOrCreateSession delegates to session store', () async {
      final inner = _TestAgent();
      final session = _TestSession(marker: 'retrieved');
      final store = _FakeSessionStore(getSessionResult: session);
      final host = AIHostAgent(inner, store);

      final result = await host.getOrCreateSession('conv-1');

      expect(result, same(session));
      expect(store.lastGetAgent, same(inner));
      expect(store.lastGetConversationId, 'conv-1');
    });

    test('saveSession delegates to session store', () async {
      final inner = _TestAgent();
      final session = _TestSession();
      final store = _FakeSessionStore(getSessionResult: session);
      final host = AIHostAgent(inner, store);

      await host.saveSession('conv-1', session);

      expect(store.lastSaveAgent, same(inner));
      expect(store.lastSaveConversationId, 'conv-1');
      expect(store.lastSaveSession, same(session));
    });

    test('delegates runCore to inner agent', () async {
      final inner = _TestAgent(responseText: 'host-response');
      final store = _FakeSessionStore(getSessionResult: _TestSession());
      final host = AIHostAgent(inner, store);

      final response = await host.runCore(
        [ChatMessage.fromText(ChatRole.user, 'hi')],
      );

      expect(response.text, 'host-response');
    });

    test('cancellationToken is passed through to store', () async {
      final inner = _TestAgent();
      final session = _TestSession();
      final store = _FakeSessionStore(getSessionResult: session);
      final host = AIHostAgent(inner, store);
      final ct = CancellationToken.none;

      await host.getOrCreateSession('conv-1', cancellationToken: ct);
      await host.saveSession('conv-1', session, cancellationToken: ct);

      expect(store.lastGetCancellationToken, same(ct));
      expect(store.lastSaveCancellationToken, same(ct));
    });
  });
}

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _TestAgent extends AIAgent {
  _TestAgent({this.responseText = 'response'});

  final String responseText;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => {'marker': (session as _TestSession).marker};

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    final map = serializedState as Map<String, dynamic>;
    return _TestSession(marker: map['marker'] as String?);
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async =>
      AgentResponse(
        message: ChatMessage.fromText(ChatRole.assistant, responseText),
      );

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    yield AgentResponseUpdate(role: ChatRole.assistant, content: responseText);
  }
}

class _TestSession extends AgentSession {
  _TestSession({this.marker}) : super(AgentSessionStateBag(null));
  final String? marker;
}

class _FakeSessionStore extends InMemoryAgentSessionStore {
  _FakeSessionStore({required this.getSessionResult});

  final AgentSession getSessionResult;
  AIAgent? lastGetAgent;
  String? lastGetConversationId;
  CancellationToken? lastGetCancellationToken;
  AIAgent? lastSaveAgent;
  String? lastSaveConversationId;
  AgentSession? lastSaveSession;
  CancellationToken? lastSaveCancellationToken;

  @override
  Future<AgentSession> getSession(
    AIAgent agent,
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async {
    lastGetAgent = agent;
    lastGetConversationId = conversationId;
    lastGetCancellationToken = cancellationToken;
    return getSessionResult;
  }

  @override
  Future saveSession(
    AIAgent agent,
    String conversationId,
    AgentSession session, {
    CancellationToken? cancellationToken,
  }) async {
    lastSaveAgent = agent;
    lastSaveConversationId = conversationId;
    lastSaveSession = session;
    lastSaveCancellationToken = cancellationToken;
  }
}
