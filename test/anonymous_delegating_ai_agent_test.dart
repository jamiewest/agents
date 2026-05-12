import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/ai/anonymous_delegating_ai_agent.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('AnonymousDelegatingAIAgent', () {
    test('throwIfBothDelegatesNull_ThrowsWhenBothNull', () {
      expect(
        () => AnonymousDelegatingAIAgent.throwIfBothDelegatesNull(null, null),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('sharedFunc_IsUsedForRunCore', () async {
      var called = false;
      final inner = _TestAgent(responseText: 'inner');
      final agent = AnonymousDelegatingAIAgent(
        inner,
        sharedFunc: (msgs, session, opts, invoker, ct) async {
          called = true;
          return AgentResponse(
            message: ChatMessage.fromText(ChatRole.assistant, 'shared'),
          );
        },
        runFunc: (msgs, session, opts, innerAgent, ct) =>
            innerAgent.runCore(msgs),
      );

      final response = await agent.runCore([]);

      expect(called, isTrue);
      expect(response.text, 'shared');
    });

    test('sharedFunc_IsUsedForStreamingCore', () async {
      var called = false;
      final inner = _TestAgent();
      final agent = AnonymousDelegatingAIAgent(
        inner,
        sharedFunc: (msgs, session, opts, invoker, ct) async {
          called = true;
          return AgentResponse(
            message: ChatMessage.fromText(ChatRole.assistant, 'streamed'),
          );
        },
        runFunc: (msgs, session, opts, innerAgent, ct) =>
            innerAgent.runCore(msgs),
      );

      final updates = await agent.runCoreStreaming([]).toList();

      expect(called, isTrue);
      expect(updates.map((u) => u.text).join(), 'streamed');
    });

    test('runFunc_IsUsedWhenNoSharedFunc', () async {
      var runCalled = false;
      final inner = _TestAgent();
      final agent = AnonymousDelegatingAIAgent(
        inner,
        runFunc: (msgs, session, opts, innerAgent, ct) async {
          runCalled = true;
          return AgentResponse(
            message: ChatMessage.fromText(ChatRole.assistant, 'run'),
          );
        },
      );

      final response = await agent.runCore([]);

      expect(runCalled, isTrue);
      expect(response.text, 'run');
    });

    test('streamingFunc_IsUsedWhenNoSharedFunc', () async {
      var streamingCalled = false;
      final inner = _TestAgent();
      final agent = AnonymousDelegatingAIAgent(
        inner,
        runStreamingFunc: (msgs, session, opts, innerAgent, ct) async* {
          streamingCalled = true;
          yield AgentResponseUpdate(
            role: ChatRole.assistant,
            content: 'stream',
          );
        },
      );

      final updates = await agent.runCoreStreaming([]).toList();

      expect(streamingCalled, isTrue);
      expect(updates.map((u) => u.text).join(), 'stream');
    });

    test('runFunc_IsUsedForRun_StreamingFuncForStreaming', () async {
      var runCalled = false;
      var streamCalled = false;
      final inner = _TestAgent();
      final agent = AnonymousDelegatingAIAgent(
        inner,
        runFunc: (msgs, session, opts, innerAgent, ct) async {
          runCalled = true;
          return AgentResponse(
            message: ChatMessage.fromText(ChatRole.assistant, 'run'),
          );
        },
        runStreamingFunc: (msgs, session, opts, innerAgent, ct) async* {
          streamCalled = true;
          yield AgentResponseUpdate(
            role: ChatRole.assistant,
            content: 'stream',
          );
        },
      );

      final runResponse = await agent.runCore([]);
      final streamUpdates = await agent.runCoreStreaming([]).toList();

      expect(runCalled, isTrue);
      expect(streamCalled, isTrue);
      expect(runResponse.text, 'run');
      expect(streamUpdates.map((u) => u.text).join(), 'stream');
    });

    test('runOnly_StreamingFallsBackToWrappingRunResponse', () async {
      final inner = _TestAgent();
      final agent = AnonymousDelegatingAIAgent(
        inner,
        runFunc: (msgs, session, opts, innerAgent, ct) async =>
            AgentResponse(
              message: ChatMessage.fromText(ChatRole.assistant, 'wrapped'),
            ),
      );

      final updates = await agent.runCoreStreaming([]).toList();

      expect(updates.map((u) => u.text).join(), 'wrapped');
    });

    test('streamingOnly_RunFallsBackToCollectingStream', () async {
      final inner = _TestAgent();
      final agent = AnonymousDelegatingAIAgent(
        inner,
        runStreamingFunc: (msgs, session, opts, innerAgent, ct) async* {
          yield AgentResponseUpdate(
            role: ChatRole.assistant,
            content: 'collected',
          );
        },
      );

      final response = await agent.runCore([]);

      expect(response.text, 'collected');
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
