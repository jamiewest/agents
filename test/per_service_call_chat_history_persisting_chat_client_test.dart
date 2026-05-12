import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_context.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/ai/chat_client/chat_client_agent.dart';
import 'package:agents/src/ai/chat_client/chat_client_agent_options.dart';
import 'package:agents/src/ai/chat_client/chat_client_agent_session.dart';
import 'package:agents/src/ai/chat_client/per_service_call_chat_history_persisting_chat_client.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  // Restore context after every test to avoid state leakage.
  tearDown(() => AIAgent.currentRunContext = null);

  group('PerServiceCallChatHistoryPersistingChatClient guard conditions', () {
    test('getResponse throws StateError when called outside an agent run', () {
      final client = PerServiceCallChatHistoryPersistingChatClient(
        _ScriptedChatClient(),
      );
      AIAgent.currentRunContext = null;

      expect(
        () => client.getResponse(messages: []),
        throwsStateError,
      );
    });

    test('getResponse throws StateError when agent is not a ChatClientAgent',
        () {
      final client = PerServiceCallChatHistoryPersistingChatClient(
        _ScriptedChatClient(),
      );
      final wrongAgent = _PlainAgent();
      AIAgent.currentRunContext = AgentRunContext(
        wrongAgent,
        ChatClientAgentSession(),
        const [],
        null,
      );

      expect(
        () => client.getResponse(messages: []),
        throwsStateError,
      );
    });

    test('getResponse throws StateError when session is not a ChatClientAgentSession',
        () {
      final innerClient = _ScriptedChatClient();
      final agent = ChatClientAgent(
        innerClient,
        options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
      );
      final client = PerServiceCallChatHistoryPersistingChatClient(
        _ScriptedChatClient(),
      );
      // Use a non-ChatClientAgentSession (plain AgentSession subclass)
      AIAgent.currentRunContext = AgentRunContext(
        agent,
        _PlainSession(),
        const [],
        null,
      );

      expect(
        () => client.getResponse(messages: []),
        throwsStateError,
      );
    });

    test('getStreamingResponse throws StateError outside an agent run', () {
      final client = PerServiceCallChatHistoryPersistingChatClient(
        _ScriptedChatClient(),
      );
      AIAgent.currentRunContext = null;

      expect(
        () => client.getStreamingResponse(messages: []).toList(),
        throwsStateError,
      );
    });
  });

  group('PerServiceCallChatHistoryPersistingChatClient getResponse', () {
    test('strips sentinel conversation id from options before forwarding', () {
      ChatOptions? captured;
      final inner = _ScriptedChatClient()
        ..onGetResponse = (_, options, _) {
          captured = options;
          return ChatResponse(messages: [
            ChatMessage.fromText(ChatRole.assistant, 'ok'),
          ]);
        };
      final client = PerServiceCallChatHistoryPersistingChatClient(inner);
      final (agent, session) = _setupRunContext(client);
      session.conversationId = localHistoryConversationId;

      agent.runCore(
        [ChatMessage.fromText(ChatRole.user, 'hi')],
        session: session,
      );

      // give the future a chance to run
      expect(captured?.conversationId, isNot(localHistoryConversationId));
    });

    test('sets sentinel conversation id on response and session when service '
        'does not return a conversation id', () async {
      final inner = _ScriptedChatClient()
        ..onGetResponse = (_, _, _) => ChatResponse(
              messages: [ChatMessage.fromText(ChatRole.assistant, 'reply')],
              conversationId: null,
            );
      final client = PerServiceCallChatHistoryPersistingChatClient(inner);
      final (agent, session) = _setupRunContext(client);

      await agent.runCore(
        [ChatMessage.fromText(ChatRole.user, 'hi')],
        session: session,
      );

      expect(session.conversationId, localHistoryConversationId);
    });

    test('preserves service-assigned conversation id', () async {
      final inner = _ScriptedChatClient()
        ..onGetResponse = (_, _, _) => ChatResponse(
              messages: [ChatMessage.fromText(ChatRole.assistant, 'reply')],
              conversationId: 'svc-conv-123',
            );
      final client = PerServiceCallChatHistoryPersistingChatClient(inner);
      final (agent, session) = _setupRunContext(client);

      await agent.runCore(
        [ChatMessage.fromText(ChatRole.user, 'hi')],
        session: session,
      );

      expect(session.conversationId, 'svc-conv-123');
    });
  });

  group('PerServiceCallChatHistoryPersistingChatClient getStreamingResponse',
      () {
    test('yields all updates from the inner client', () async {
      final inner = _ScriptedChatClient()
        ..onGetStreamingResponse = (_, _, _) async* {
          yield ChatResponseUpdate.fromText(ChatRole.assistant, 'part1');
          yield ChatResponseUpdate.fromText(ChatRole.assistant, 'part2');
        };
      final client = PerServiceCallChatHistoryPersistingChatClient(inner);
      final (agent, session) = _setupRunContext(client);

      final updates = await agent
          .runCoreStreaming(
            [ChatMessage.fromText(ChatRole.user, 'hi')],
            session: session,
          )
          .toList();

      expect(updates.map((u) => u.text).join(), 'part1part2');
    });

    test('sets sentinel conversation id on session when streaming completes '
        'without a service conversation id', () async {
      final inner = _ScriptedChatClient()
        ..onGetStreamingResponse = (_, _, _) async* {
          yield ChatResponseUpdate.fromText(ChatRole.assistant, 'stream');
        };
      final client = PerServiceCallChatHistoryPersistingChatClient(inner);
      final (agent, session) = _setupRunContext(client);

      await agent
          .runCoreStreaming(
            [ChatMessage.fromText(ChatRole.user, 'hi')],
            session: session,
          )
          .toList();

      expect(session.conversationId, localHistoryConversationId);
    });
  });

  group('setSentinelConversationId', () {
    test('sets sentinel id on both response and session', () {
      final response = ChatResponse(
        messages: [ChatMessage.fromText(ChatRole.assistant, 'x')],
      );
      final session = ChatClientAgentSession();

      PerServiceCallChatHistoryPersistingChatClient.setSentinelConversationId(
        response,
        session,
      );

      expect(response.conversationId, localHistoryConversationId);
      expect(session.conversationId, localHistoryConversationId);
    });
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Sets up an agent-with-persisting-client run context and returns the
/// agent/session pair so tests can call [runCore] directly.
(ChatClientAgent, ChatClientAgentSession) _setupRunContext(
  PerServiceCallChatHistoryPersistingChatClient persistingClient,
) {
  final agent = ChatClientAgent(
    persistingClient,
    options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
  );
  final session = ChatClientAgentSession();
  AIAgent.currentRunContext = AgentRunContext(agent, session, const [], null);
  return (agent, session);
}

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _ScriptedChatClient implements ChatClient {
  ChatResponse Function(
    Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  )?
  onGetResponse;

  Stream<ChatResponseUpdate> Function(
    Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  )?
  onGetStreamingResponse;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    return onGetResponse?.call(messages, options, cancellationToken) ??
        ChatResponse(
          messages: [ChatMessage.fromText(ChatRole.assistant, 'response')],
        );
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final stream =
        onGetStreamingResponse?.call(messages, options, cancellationToken);
    if (stream == null) {
      yield ChatResponseUpdate.fromText(ChatRole.assistant, 'response');
      return;
    }
    yield* stream;
  }

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}
}

/// A plain [AIAgent] that is not a [ChatClientAgent].
class _PlainAgent extends AIAgent {
  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _PlainSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => {};

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _PlainSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async =>
      AgentResponse(
        message: ChatMessage.fromText(ChatRole.assistant, 'response'),
      );

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    yield AgentResponseUpdate(role: ChatRole.assistant, content: 'response');
  }
}

/// An [AgentSession] that is not a [ChatClientAgentSession].
class _PlainSession extends AgentSession {
  _PlainSession() : super(AgentSessionStateBag(null));
}
