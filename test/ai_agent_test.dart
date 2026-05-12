import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('AIAgent', () {
    test('invokeWithoutMessageCallsMockedInvokeWithEmptyArray', () async {
      final agent = _TestAgent();

      await agent.run(null, null);

      expect(agent.capturedMessages, isEmpty);
    });

    test(
      'invokeWithStringMessageCallsMockedInvokeWithMessageInCollection',
      () async {
        final agent = _TestAgent();

        await agent.run(null, null, message: 'hi');

        expect(agent.capturedMessages, hasLength(1));
        expect(agent.capturedMessages.first.role, ChatRole.user);
        expect(agent.capturedMessages.first.text, 'hi');
      },
    );

    test(
      'invokeWithSingleMessageCallsMockedInvokeWithMessageInCollection',
      () async {
        final agent = _TestAgent();
        final msg = ChatMessage.fromText(ChatRole.user, 'hello');

        await agent.run(null, null, messages: [msg]);

        expect(agent.capturedMessages, hasLength(1));
        expect(agent.capturedMessages.first, same(msg));
      },
    );

    test(
      'invokeStreamingWithoutMessageCallsMockedInvokeWithEmptyArray',
      () async {
        final agent = _TestAgent();

        await agent.runStreaming(null, null).toList();

        expect(agent.capturedMessages, isEmpty);
      },
    );

    test(
      'invokeStreamingWithStringMessageCallsMockedInvokeWithMessageInCollection',
      () async {
        final agent = _TestAgent();

        await agent.runStreaming(null, null, message: 'hi').toList();

        expect(agent.capturedMessages, hasLength(1));
        expect(agent.capturedMessages.first.role, ChatRole.user);
        expect(agent.capturedMessages.first.text, 'hi');
      },
    );

    test(
      'invokeStreamingWithSingleMessageCallsMockedInvokeWithMessageInCollection',
      () async {
        final agent = _TestAgent();
        final msg = ChatMessage.fromText(ChatRole.user, 'hello');

        await agent.runStreaming(null, null, messages: [msg]).toList();

        expect(agent.capturedMessages, hasLength(1));
        expect(agent.capturedMessages.first, same(msg));
      },
    );

    test('validateAgentIDIsIdempotent', () {
      final agent = _TestAgent();

      final id1 = agent.id;
      final id2 = agent.id;

      expect(id1, id2);
    });

    test('getService_RequestingAIAgentType_ReturnsAgent', () {
      final agent = _TestAgent();

      final service = agent.getService(AIAgent);

      expect(service, same(agent));
    });

    test('getService_RequestingUnrelatedType_ReturnsNull', () {
      final agent = _TestAgent();

      final service = agent.getService(String);

      expect(service, isNull);
    });

    test(
      'getService_WithServiceKey_StillReturnsAgentForAIAgentType',
      () {
        final agent = _TestAgent();

        final service = agent.getService(AIAgent, serviceKey: 'key');

        expect(service, same(agent));
      },
    );

    test('getService_Generic_ReturnsCorrectType', () {
      final agent = _TestAgent();

      final service = agent.getServiceOf<AIAgent>();

      expect(service, isNotNull);
    });

    test('getService_Generic_ReturnsNullForUnrelatedType', () {
      final agent = _TestAgent();

      final service = agent.getServiceOf<String>();

      expect(service, isNull);
    });

    test('name_ReturnsNullByDefault', () {
      final agent = _TestAgent();

      expect(agent.name, isNull);
    });

    test('description_ReturnsNullByDefault', () {
      final agent = _TestAgent();

      expect(agent.description, isNull);
    });

    test('name_ReturnsValueFromDerivedClass', () {
      final agent = _TestAgent(nameValue: 'MyAgent');

      expect(agent.name, 'MyAgent');
    });

    test('description_ReturnsValueFromDerivedClass', () {
      final agent = _TestAgent(descriptionValue: 'Does things');

      expect(agent.description, 'Does things');
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
  List<ChatMessage> capturedMessages = [];
  AgentSession? capturedSession;
  AgentRunOptions? capturedOptions;
  CancellationToken? capturedCancellationToken;

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
    capturedMessages = messages.toList();
    capturedSession = session;
    capturedOptions = options;
    capturedCancellationToken = cancellationToken;
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
    capturedMessages = messages.toList();
    capturedSession = session;
    yield AgentResponseUpdate(
      role: ChatRole.assistant,
      content: responseText,
    );
  }
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}
