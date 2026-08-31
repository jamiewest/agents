import 'package:agents/src/abstractions/agent_run_context.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/ai/chat_client/route_persisting_routing_chat_client.dart';
import 'package:agents/src/ai/chat_client/route_persisting_routing_chat_client_options.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  late _TestSession session;

  setUp(() {
    session = _TestSession();
    AIAgent.currentRunContext = AgentRunContext(
      _StubAgent(),
      session,
      <ChatMessage>[],
      null,
    );
  });

  tearDown(() => AIAgent.currentRunContext = null);

  group('RoutePersistingRoutingChatClient', () {
    test('routes to the default route for a new session', () async {
      final fast = _NamedClient('fast');
      final smart = _NamedClient('smart');
      final router = RoutePersistingRoutingChatClient({
        'fast': fast,
        'smart': smart,
      });

      final response = await router.getResponse(messages: [_user('hi')]);

      expect(response.text, 'fast');
      expect(fast.calls, 1);
      expect(smart.calls, 0);
      expect(router.getActiveRoute(session), 'fast');
    });

    test('honors an explicitly configured default route', () async {
      final router = RoutePersistingRoutingChatClient(
        {'fast': _NamedClient('fast'), 'smart': _NamedClient('smart')},
        options: RoutePersistingRoutingChatClientOptions(defaultRoute: 'smart'),
      );

      final response = await router.getResponse(messages: [_user('hi')]);

      expect(response.text, 'smart');
    });

    test('setActiveRoute switches the routed client for the session', () async {
      final fast = _NamedClient('fast');
      final smart = _NamedClient('smart');
      final router = RoutePersistingRoutingChatClient({
        'fast': fast,
        'smart': smart,
      });

      await router.getResponse(messages: [_user('one')]);
      router.setActiveRoute(session, 'smart');
      final response = await router.getResponse(messages: [_user('two')]);

      expect(response.text, 'smart');
      expect(fast.calls, 1);
      expect(smart.calls, 1);
      expect(router.getActiveRoute(session), 'smart');
    });

    test('the active route survives session serialization', () async {
      final router = RoutePersistingRoutingChatClient({
        'fast': _NamedClient('fast'),
        'smart': _NamedClient('smart'),
      });
      router.setActiveRoute(session, 'smart');

      // Simulate a restored session: the bag holds the raw JSON-decoded
      // value rather than the typed state.
      final raw = session.stateBag.getValue<Object>(
        'RoutePersistingRoutingChatClient',
      );
      final restored = _TestSession();
      restored.stateBag.setValue<Object>('RoutePersistingRoutingChatClient', {
        'activeRoute': 'smart',
      });
      expect(raw, isNotNull);

      expect(router.getActiveRoute(restored), 'smart');
    });

    test('setActiveRoute rejects an unregistered route', () {
      final router = RoutePersistingRoutingChatClient({
        'fast': _NamedClient('fast'),
      });

      expect(
        () => router.setActiveRoute(session, 'missing'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws without a run context', () async {
      AIAgent.currentRunContext = null;
      final router = RoutePersistingRoutingChatClient({
        'fast': _NamedClient('fast'),
      });

      await expectLater(
        () => router.getResponse(messages: [_user('hi')]),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when the run context has no session', () async {
      AIAgent.currentRunContext = AgentRunContext(
        _StubAgent(),
        null,
        <ChatMessage>[],
        null,
      );
      final router = RoutePersistingRoutingChatClient({
        'fast': _NamedClient('fast'),
      });

      await expectLater(
        () => router.getResponse(messages: [_user('hi')]),
        throwsA(isA<StateError>()),
      );
    });

    test('getService returns itself and forwards to the active route', () {
      final fast = _NamedClient('fast');
      final router = RoutePersistingRoutingChatClient({'fast': fast});

      expect(
        router.getService<RoutePersistingRoutingChatClient>(),
        same(router),
      );
      expect(router.getService<_NamedClient>(), same(fast));
    });

    test('dispose disposes owned inner clients once each', () {
      final shared = _NamedClient('shared');
      final router = RoutePersistingRoutingChatClient(
        {'a': shared, 'b': shared},
        options: RoutePersistingRoutingChatClientOptions(
          ownsInnerClients: true,
        ),
      );

      router.dispose();
      router.dispose();

      expect(shared.disposeCount, 1);
    });

    test('dispose leaves unowned inner clients alone', () {
      final client = _NamedClient('fast');
      final router = RoutePersistingRoutingChatClient({'fast': client});

      router.dispose();

      expect(client.disposeCount, 0);
    });
  });
}

ChatMessage _user(String text) => ChatMessage.fromText(ChatRole.user, text);

class _NamedClient implements ChatClient {
  _NamedClient(this.name);

  final String name;
  int calls = 0;
  int disposeCount = 0;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    calls++;
    return ChatResponse.fromMessage(
      ChatMessage.fromText(ChatRole.assistant, name),
    );
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    calls++;
    yield ChatResponseUpdate(
      role: ChatRole.assistant,
      contents: [TextContent(name)],
    );
  }

  @override
  T? getService<T>({Object? key}) => this is T ? this as T : null;

  @override
  void dispose() {
    disposeCount++;
  }
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

class _StubAgent extends AIAgent {
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
  }) async => null;

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async => AgentResponse();

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) => const Stream.empty();
}
