// ignore_for_file: non_constant_identifier_names
import 'package:a2a/a2a.dart';
import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/a2a/a2a_continuation_token.dart';
import 'package:agents/src/hosting/a2a/a2a_agent_handler.dart';
import 'package:agents/src/hosting/a2a/agent_run_mode.dart';
import 'package:agents/src/hosting/agent_session_store.dart';
import 'package:agents/src/hosting/ai_host_agent.dart';
import 'package:agents/src/hosting/local/in_memory_agent_session_store.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

A2AMessage _userMessage(String text, {List<String>? referenceTaskIds}) =>
    A2AMessage()
      ..role = 'user'
      ..parts = [A2ATextPart()..text = text]
      ..referenceTaskIds = referenceTaskIds;

A2ARequestContext _request(A2AMessage message, {A2ATask? task}) =>
    A2ARequestContext(message, task, null, 'task-1', 'ctx-1');

A2AAgentHandler _handler(
  AIAgent agent, {
  AgentRunMode? runMode,
  AgentSessionStore? store,
}) => A2AAgentHandler(
  AIHostAgent(agent, store ?? InMemoryAgentSessionStore()),
  runMode ?? AgentRunMode.disallowBackground,
);

void main() {
  group('A2AAgentHandler.execute (new message)', () {
    test(
      'publishes a single agent message when there is no continuation',
      () async {
        final agent = _FakeAgent(
          responseBuilder: () => AgentResponse(
            message: ChatMessage.fromText(ChatRole.assistant, 'hi there'),
          )..responseId = 'resp-1',
        );
        final bus = _CapturingEventBus();

        await _handler(agent).execute(_request(_userMessage('hello')), bus);

        final messages = bus.published.whereType<A2AMessage>().toList();
        expect(messages, hasLength(1));
        expect(messages.single.role, 'agent');
        expect(messages.single.messageId, 'resp-1');
        expect(messages.single.contextId, 'ctx-1');
        expect((messages.single.parts!.single as A2ATextPart).text, 'hi there');
        expect(bus.finishedCalled, isTrue);
        expect(
          (agent.receivedMessages.single.contents.single as TextContent).text,
          'hello',
        );
      },
    );

    test(
      'emits submitted then working status when a continuation is present',
      () async {
        final agent = _FakeAgent(
          responseBuilder: () => AgentResponse(
            message: ChatMessage.fromText(ChatRole.assistant, 'working on it'),
          )..continuationToken = A2AContinuationToken('t-1'),
        );
        final bus = _CapturingEventBus();

        await _handler(
          agent,
          runMode: AgentRunMode.allowBackgroundIfSupported,
        ).execute(_request(_userMessage('do work')), bus);

        final statuses = bus.published
            .whereType<A2ATaskStatusUpdateEvent>()
            .toList();
        expect(statuses.map((s) => s.status!.state), [
          A2ATaskState.submitted,
          A2ATaskState.working,
        ]);
        expect(statuses.last.status!.message, isNotNull);
      },
    );

    test('throws when the message references prior tasks', () async {
      final agent = _FakeAgent();
      final bus = _CapturingEventBus();

      await expectLater(
        _handler(agent).execute(
          _request(_userMessage('hi', referenceTaskIds: ['prior'])),
          bus,
        ),
        throwsUnsupportedError,
      );
    });

    test('saves the session even when the run throws', () async {
      final agent = _FakeAgent(throwOnRun: true);
      final store = _RecordingStore();
      final bus = _CapturingEventBus();

      await expectLater(
        _handler(
          agent,
          store: store,
        ).execute(_request(_userMessage('hi')), bus),
        throwsA(isA<StateError>()),
      );
      expect(store.saveCount, 1);
    });
  });

  group('A2AAgentHandler.execute (task update)', () {
    test('completes with an artifact when there is no continuation', () async {
      final agent = _FakeAgent(
        responseBuilder: () => AgentResponse(
          message: ChatMessage.fromText(ChatRole.assistant, 'the answer'),
        ),
      );
      final bus = _CapturingEventBus();
      final task = A2ATask()..history = [_userMessage('question')];

      await _handler(
        agent,
      ).execute(_request(_userMessage('question'), task: task), bus);

      final artifacts = bus.published
          .whereType<A2ATaskArtifactUpdateEvent>()
          .toList();
      expect(artifacts, hasLength(1));
      expect(
        (artifacts.single.artifact!.parts.single as A2ATextPart).text,
        'the answer',
      );
      final statuses = bus.published
          .whereType<A2ATaskStatusUpdateEvent>()
          .toList();
      expect(statuses.single.status!.state, A2ATaskState.completed);
      expect(statuses.single.end, isTrue);
    });

    test(
      'publishes a failed status and rethrows when the run throws',
      () async {
        final agent = _FakeAgent(throwOnRun: true);
        final bus = _CapturingEventBus();
        final task = A2ATask()..history = [_userMessage('question')];

        await expectLater(
          _handler(
            agent,
          ).execute(_request(_userMessage('question'), task: task), bus),
          throwsA(isA<StateError>()),
        );
        final statuses = bus.published
            .whereType<A2ATaskStatusUpdateEvent>()
            .toList();
        expect(statuses.single.status!.state, A2ATaskState.failed);
      },
    );
  });

  group('A2AAgentHandler.cancelTask', () {
    test('publishes a canceled status event', () async {
      final bus = _CapturingEventBus();

      await _handler(_FakeAgent()).cancelTask('task-9', bus);

      final statuses = bus.published
          .whereType<A2ATaskStatusUpdateEvent>()
          .toList();
      expect(statuses.single.status!.state, A2ATaskState.canceled);
      expect(statuses.single.end, isTrue);
      expect(bus.finishedCalled, isTrue);
    });
  });
}

class _CapturingEventBus extends A2ADefaultExecutionEventBus {
  final List<Object> published = [];
  bool finishedCalled = false;

  @override
  void publish(A2AAgentExecutionEvent event) {
    published.add(event);
    super.publish(event);
  }

  @override
  void finished() {
    finishedCalled = true;
    super.finished();
  }
}

class _RecordingStore extends AgentSessionStore {
  final InMemoryAgentSessionStore _inner = InMemoryAgentSessionStore();
  int saveCount = 0;

  @override
  Future<AgentSession> getSession(
    AIAgent agent,
    String conversationId, {
    CancellationToken? cancellationToken,
  }) => _inner.getSession(
    agent,
    conversationId,
    cancellationToken: cancellationToken,
  );

  @override
  Future saveSession(
    AIAgent agent,
    String conversationId,
    AgentSession session, {
    CancellationToken? cancellationToken,
  }) {
    saveCount++;
    return _inner.saveSession(
      agent,
      conversationId,
      session,
      cancellationToken: cancellationToken,
    );
  }
}

class _FakeAgent extends AIAgent {
  _FakeAgent({this.responseBuilder, this.throwOnRun = false});

  final AgentResponse Function()? responseBuilder;
  final bool throwOnRun;
  List<ChatMessage> receivedMessages = const [];

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _FakeSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => '{}';

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _FakeSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    receivedMessages = messages.toList();
    if (throwOnRun) {
      throw StateError('boom');
    }
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
    yield AgentResponseUpdate(role: ChatRole.assistant, content: 'ok');
  }
}

class _FakeSession extends AgentSession {
  _FakeSession() : super(AgentSessionStateBag(null));
}
