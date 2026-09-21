import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/ai/agent_extensions.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('AIAgent.asChatClient argument validation', () {
    test('rejects a conversation id without a session', () {
      expect(
        () => _FakeAgent().asChatClient(
          conversationId: 'c1',
          allowNonChatClientAgents: true,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a blank conversation id', () {
      expect(
        () => _FakeAgent().asChatClient(
          session: _TestSession(),
          conversationId: '   ',
          allowNonChatClientAgents: true,
        ),
        throwsArgumentError,
      );
    });

    test('rejects the reserved local-history conversation id', () {
      expect(
        () => _FakeAgent().asChatClient(
          session: _TestSession(),
          conversationId: '__perServiceCallChatHistoryPersistence__',
          allowNonChatClientAgents: true,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a non-ChatClientAgent unless opted in', () {
      expect(() => _FakeAgent().asChatClient(), throwsStateError);
    });
  });

  group('AIAgentChatClient stateless', () {
    test('reports no conversation id and clears the agent\'s', () async {
      final agent = _FakeAgent(
        responseBuilder: () =>
            AgentResponse(
                message: ChatMessage.fromText(ChatRole.assistant, 'hi'),
              )
              ..additionalProperties = (AdditionalPropertiesDictionary()
                ..['k'] = 'v'),
      );
      final client = agent.asChatClient(allowNonChatClientAgents: true);

      final response = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hello')],
      );

      expect(response.conversationId, isNull);
      // Only the conversation id is withheld.
      expect(response.additionalProperties?['k'], 'v');
      expect(response.text, 'hi');
    });

    test('rejects a caller-supplied conversation id', () async {
      final client = _FakeAgent().asChatClient(allowNonChatClientAgents: true);

      await expectLater(
        client.getResponse(
          messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
          options: ChatOptions()..conversationId = 'someone-elses',
        ),
        throwsStateError,
      );
    });

    test('treats a blank conversation id as absent', () async {
      final agent = _FakeAgent();
      final client = agent.asChatClient(allowNonChatClientAgents: true);

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
        options: ChatOptions()..conversationId = '  ',
      );

      expect(_forwardedConversationId(agent), isNull);
    });

    test('does not mutate the caller-supplied options', () async {
      final agent = _FakeAgent();
      final client = agent.asChatClient(allowNonChatClientAgents: true);
      final options = ChatOptions()..conversationId = '';

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
        options: options,
      );

      expect(options.conversationId, '');
    });
  });

  group('AIAgentChatClient session-bound', () {
    test('reports the supplied conversation id on every response', () async {
      final agent = _FakeAgent();
      final client = agent.asChatClient(
        session: _TestSession(),
        conversationId: 'fixed',
        allowNonChatClientAgents: true,
      );

      final first = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'a')],
      );
      final second = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'b')],
      );

      expect(first.conversationId, 'fixed');
      expect(second.conversationId, 'fixed');
    });

    test('accepts its own id echoed back and strips it', () async {
      final agent = _FakeAgent();
      final client = agent.asChatClient(
        session: _TestSession(),
        conversationId: 'fixed',
        allowNonChatClientAgents: true,
      );

      final response = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'a')],
        options: ChatOptions()..conversationId = 'fixed',
      );

      expect(response.conversationId, 'fixed');
      expect(_forwardedConversationId(agent), isNull);
    });

    test('rejects any other conversation id', () async {
      final client = _FakeAgent().asChatClient(
        session: _TestSession(),
        conversationId: 'fixed',
        allowNonChatClientAgents: true,
      );

      await expectLater(
        client.getResponse(
          messages: [ChatMessage.fromText(ChatRole.user, 'a')],
          options: ChatOptions()..conversationId = 'other',
        ),
        throwsStateError,
      );
    });

    test('re-stamps a service-minted id on streamed updates', () async {
      // A conversation id reaches the adapter through the raw
      // ChatResponseUpdate the agent carries.
      final raw = ChatResponseUpdate(
        role: ChatRole.assistant,
        contents: [TextContent('a')],
      )..conversationId = 'service-side';
      final agent = _FakeAgent(
        updatesBuilder: () => [AgentResponseUpdate(chatResponseUpdate: raw)],
      );
      final client = agent.asChatClient(
        session: _TestSession(),
        conversationId: 'fixed',
        allowNonChatClientAgents: true,
      );

      final updates = await client
          .getStreamingResponse(
            messages: [ChatMessage.fromText(ChatRole.user, 'a')],
          )
          .toList();

      expect(updates.single.conversationId, 'fixed');
      // The agent's own update is left unmodified.
      expect(raw.conversationId, 'service-side');
    });

    test('yields an id-only update for an empty stream', () async {
      final agent = _FakeAgent(updatesBuilder: () => const []);
      final client = agent.asChatClient(
        session: _TestSession(),
        conversationId: 'fixed',
        allowNonChatClientAgents: true,
      );

      final updates = await client
          .getStreamingResponse(
            messages: [ChatMessage.fromText(ChatRole.user, 'a')],
          )
          .toList();

      expect(updates, hasLength(1));
      expect(updates.single.conversationId, 'fixed');
      expect(updates.single.contents, isEmpty);
    });

    test('a stateless empty stream yields nothing', () async {
      final agent = _FakeAgent(updatesBuilder: () => const []);
      final client = agent.asChatClient(allowNonChatClientAgents: true);

      final updates = await client
          .getStreamingResponse(
            messages: [ChatMessage.fromText(ChatRole.user, 'a')],
          )
          .toList();

      expect(updates, isEmpty);
    });

    test('generates a stable id when none is supplied', () async {
      final client = _FakeAgent().asChatClient(
        session: _TestSession(),
        allowNonChatClientAgents: true,
      );

      final first = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'a')],
      );
      final second = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'b')],
      );

      expect(first.conversationId, isNotEmpty);
      expect(second.conversationId, first.conversationId);
    });

    test('a generated id is not shared across clients', () async {
      final agent = _FakeAgent();
      final a = agent.asChatClient(
        session: _TestSession(),
        allowNonChatClientAgents: true,
      );
      final b = agent.asChatClient(
        session: _TestSession(),
        allowNonChatClientAgents: true,
      );

      final fromA = await a.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'a')],
      );
      final fromB = await b.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'b')],
      );

      expect(fromA.conversationId, isNot(fromB.conversationId));
    });
  });

  group('AIAgentChatClient options mapping', () {
    test('surfaces the response format on the base run options', () async {
      final agent = _FakeAgent();
      final client = agent.asChatClient(allowNonChatClientAgents: true);
      final format = ChatResponseFormat.json;

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'a')],
        options: ChatOptions()..responseFormat = format,
      );

      expect(agent.receivedOptions?.responseFormat, same(format));
    });

    test('forwards no run options when none were supplied', () async {
      final agent = _FakeAgent();
      final client = agent.asChatClient(allowNonChatClientAgents: true);

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'a')],
      );

      expect(agent.receivedOptions, isNull);
    });
  });
}

class _FakeAgent extends AIAgent {
  _FakeAgent({this.responseBuilder, this.updatesBuilder});

  final AgentResponse Function()? responseBuilder;
  final List<AgentResponseUpdate> Function()? updatesBuilder;

  AgentRunOptions? receivedOptions;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => <String, Object?>{};

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    receivedOptions = options;
    return responseBuilder?.call() ??
        AgentResponse(message: ChatMessage.fromText(ChatRole.assistant, 'ok'));
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    receivedOptions = options;
    for (final update
        in updatesBuilder?.call() ??
            [AgentResponseUpdate(role: ChatRole.assistant, content: 'ok')]) {
      yield update;
    }
  }
}

String? _forwardedConversationId(_FakeAgent agent) =>
    ((agent.receivedOptions as dynamic)?.chatOptions as ChatOptions?)
        ?.conversationId;

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}
