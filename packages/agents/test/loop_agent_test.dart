import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/ai/harness/agent_mode/agent_mode_provider.dart';
import 'package:agents/src/ai/harness/background_agents/background_agent_state.dart';
import 'package:agents/src/ai/harness/background_agents/background_agents_provider.dart';
import 'package:agents/src/ai/harness/background_agents/background_task_info.dart';
import 'package:agents/src/ai/harness/background_agents/background_task_status.dart';
import 'package:agents/src/ai/harness/loop/ai_judge_loop_evaluator.dart';
import 'package:agents/src/ai/harness/loop/background_task_completion_loop_evaluator.dart';
import 'package:agents/src/ai/harness/loop/completion_marker_loop_evaluator.dart';
import 'package:agents/src/ai/harness/loop/completion_marker_loop_evaluator_options.dart';
import 'package:agents/src/ai/harness/loop/delegate_loop_evaluator.dart';
import 'package:agents/src/ai/harness/loop/loop_agent.dart';
import 'package:agents/src/ai/harness/loop/loop_agent_options.dart';
import 'package:agents/src/ai/harness/loop/loop_context.dart';
import 'package:agents/src/ai/harness/loop/loop_evaluation.dart';
import 'package:agents/src/ai/harness/loop/loop_evaluator.dart';
import 'package:agents/src/ai/harness/loop/todo_completion_loop_evaluator.dart';
import 'package:agents/src/ai/harness/loop/todo_completion_loop_evaluator_options.dart';
import 'package:agents/src/ai/harness/todo/todo_item.dart';
import 'package:agents/src/ai/harness/todo/todo_provider.dart';
import 'package:agents/src/ai/harness/todo/todo_state.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('LoopAgent construction', () {
    test('rejects an empty evaluator list', () {
      expect(
        () => LoopAgent.withEvaluators(_ScriptedAgent(), const []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects maxIterations below 1', () {
      expect(
        () => LoopAgent(
          _ScriptedAgent(),
          _StopEvaluator(),
          options: LoopAgentOptions()..maxIterations = 0,
        ),
        throwsA(isA<RangeError>()),
      );
    });
  });

  group('LoopAgent run loop', () {
    test('stops after one iteration when the evaluator stops', () async {
      final inner = _ScriptedAgent(responses: [_text('only')]);
      final agent = LoopAgent(inner, _StopEvaluator());

      final response = await agent.runCore([_userText('go')]);

      expect(response.text, 'only');
      expect(inner.runCount, 1);
    });

    test('reuses the session and injects feedback as next input', () async {
      final inner = _ScriptedAgent(responses: [_text('r1'), _text('r2')]);
      final agent = LoopAgent(
        inner,
        _QueueEvaluator([LoopEvaluation.proceed('do more')]),
        options: LoopAgentOptions()..onBehalfOfAuthorName = 'loop',
      );

      final response = await agent.runCore([_userText('go')]);

      // Transcript: r1 + injected feedback + r2.
      expect(response.text, 'r1do morer2');
      expect(inner.runCount, 2);
      final secondRun = inner.capturedRuns[1];
      expect(secondRun.single.text, 'do more');
      expect(secondRun.single.authorName, 'loop');
    });

    test(
      'first evaluator that reinvokes wins; later ones are skipped',
      () async {
        final inner = _ScriptedAgent(responses: [_text('r1'), _text('r2')]);
        final winner = _QueueEvaluator([LoopEvaluation.proceed('keep going')]);
        final ignored = _QueueEvaluator(const []); // always stops
        final agent = LoopAgent.withEvaluators(inner, [winner, ignored]);

        await agent.runCore([_userText('go')]);

        // Iteration 1: winner reinvokes, so ignored is never consulted.
        // Iteration 2: winner stops, then ignored is consulted (and stops).
        expect(winner.calls, 2);
        expect(ignored.calls, 1);
      },
    );

    test('enforces the max-iterations cap', () async {
      final inner = _ScriptedAgent(responses: [_text('a'), _text('b')]);
      final agent = LoopAgent(
        inner,
        _AlwaysProceed(),
        options: LoopAgentOptions()..maxIterations = 2,
      );

      await agent.runCore([_userText('go')]);

      expect(inner.runCount, 2);
    });

    test('halts and surfaces a pending tool-approval request', () async {
      final approval = ToolApprovalRequestContent(
        requestId: 'r1',
        toolCall: _FunctionToolCall(callId: 'c1', name: 'Tool'),
      );
      final inner = _ScriptedAgent(
        responses: [
          AgentResponse(
            message: ChatMessage(
              role: ChatRole.assistant,
              contents: [approval],
            ),
          ),
        ],
      );
      final evaluator = _AlwaysProceed();
      final agent = LoopAgent(inner, evaluator);

      final response = await agent.runCore([_userText('go')]);

      expect(inner.runCount, 1);
      expect(evaluator.calls, 0);
      expect(
        response.messages
            .expand((m) => m.contents)
            .whereType<ToolApprovalRequestContent>(),
        hasLength(1),
      );
    });

    test('returns only the last response when configured', () async {
      final inner = _ScriptedAgent(responses: [_text('r1'), _text('r2')]);
      final agent = LoopAgent(
        inner,
        _QueueEvaluator([LoopEvaluation.proceed('again')]),
        options: LoopAgentOptions()..nonStreamingReturnsLastResponseOnly = true,
      );

      final response = await agent.runCore([_userText('go')]);

      expect(response.text, 'r2');
    });

    test('excludes on-behalf-of messages from output but still sends '
        'them', () async {
      final inner = _ScriptedAgent(responses: [_text('r1'), _text('r2')]);
      final agent = LoopAgent(
        inner,
        _QueueEvaluator([LoopEvaluation.proceed('hidden')]),
        options: LoopAgentOptions()..excludeOnBehalfOfMessages = true,
      );

      final response = await agent.runCore([_userText('go')]);

      expect(response.text, 'r1r2');
      expect(inner.capturedRuns[1].single.text, 'hidden');
    });

    test('proceedWithMessages sends explicit messages verbatim', () async {
      final inner = _ScriptedAgent(responses: [_text('r1'), _text('r2')]);
      final custom = ChatMessage.fromText(ChatRole.user, 'custom next');
      final agent = LoopAgent(
        inner,
        _QueueEvaluator([
          LoopEvaluation.proceedWithMessages([custom]),
        ]),
      );

      await agent.runCore([_userText('go')]);

      expect(inner.capturedRuns[1].single.text, 'custom next');
    });

    test('fresh context replays initial messages plus feedback and resets '
        'the session', () async {
      final inner = _ScriptedAgent(responses: [_text('r1'), _text('r2')]);
      final agent = LoopAgent(
        inner,
        _QueueEvaluator([LoopEvaluation.proceed('refine')]),
        options: LoopAgentOptions()..freshContextPerIteration = true,
      );

      await agent.runCore([_userText('go')]);

      // No caller session: one created up front, one per re-invocation.
      expect(inner.createSessionCount, 2);
      final secondRun = inner.capturedRuns[1];
      expect(secondRun.first.text, 'go');
      expect(secondRun.last.text, contains('## Feedback'));
      expect(secondRun.last.text, contains('refine'));
    });

    test(
      'invokes the session-created callback for loop-owned sessions',
      () async {
        var callbackCount = 0;
        final inner = _ScriptedAgent(responses: [_text('only')]);
        final agent = LoopAgent(
          inner,
          _StopEvaluator(),
          options: LoopAgentOptions()
            ..sessionCreatedCallback = (session, token) async {
              callbackCount++;
            },
        );

        await agent.runCore([_userText('go')]);

        expect(callbackCount, 1);
      },
    );

    test(
      'streaming yields per-iteration updates and injected feedback',
      () async {
        final inner = _ScriptedAgent(
          streams: [
            [AgentResponseUpdate(role: ChatRole.assistant, content: 'r1')],
            [AgentResponseUpdate(role: ChatRole.assistant, content: 'r2')],
          ],
        );
        final agent = LoopAgent(
          inner,
          _QueueEvaluator([LoopEvaluation.proceed('do more')]),
        );

        final updates = await agent.runCoreStreaming([
          _userText('go'),
        ]).toList();

        expect(updates.map((u) => u.text).join(), 'r1do morer2');
      },
    );
  });

  group('CompletionMarkerLoopEvaluator', () {
    test('rejects a blank marker', () {
      expect(
        () => CompletionMarkerLoopEvaluator('   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('stops when the marker is present', () async {
      final evaluator = CompletionMarkerLoopEvaluator('DONE');

      final result = await evaluator.evaluate(_contextWith('all DONE here'));

      expect(result.shouldReinvoke, isFalse);
    });

    test('continues with the marker substituted into the feedback', () async {
      final evaluator = CompletionMarkerLoopEvaluator('DONE');

      final result = await evaluator.evaluate(_contextWith('still working'));

      expect(result.shouldReinvoke, isTrue);
      expect(result.feedback, contains("'DONE'"));
    });

    test('substitutes the last-response placeholder per evaluation', () async {
      final evaluator = CompletionMarkerLoopEvaluator(
        'DONE',
        options: CompletionMarkerLoopEvaluatorOptions()
          ..feedbackMessageTemplate = 'prev: {last_response}',
      );

      final result = await evaluator.evaluate(_contextWith('abc'));

      expect(result.feedback, 'prev: abc');
    });
  });

  group('DelegateLoopEvaluator', () {
    test('delegates to the supplied callback', () async {
      final evaluator = DelegateLoopEvaluator(
        (context, {cancellationToken}) async =>
            LoopEvaluation.proceed('from delegate'),
      );

      final result = await evaluator.evaluate(_contextWith('x'));

      expect(result.feedback, 'from delegate');
    });
  });

  group('AIJudgeLoopEvaluator', () {
    test('stops on a structured answered verdict', () async {
      final evaluator = AIJudgeLoopEvaluator(
        _FakeJudge('{"answered": true, "gapAnalysis": ""}'),
      );

      final result = await evaluator.evaluate(_contextWith('partial'));

      expect(result.shouldReinvoke, isFalse);
    });

    test('continues with the gap analysis on a not-answered verdict', () async {
      final evaluator = AIJudgeLoopEvaluator(
        _FakeJudge('{"answered": false, "gapAnalysis": "missing X"}'),
      );

      final result = await evaluator.evaluate(_contextWith('partial'));

      expect(result.shouldReinvoke, isTrue);
      expect(result.feedback, contains('missing X'));
    });

    test('falls back to the DONE marker for non-structured output', () async {
      final evaluator = AIJudgeLoopEvaluator(_FakeJudge('VERDICT: DONE'));

      final result = await evaluator.evaluate(_contextWith('partial'));

      expect(result.shouldReinvoke, isFalse);
    });

    test('falls back to MORE winning on ambiguous output', () async {
      final evaluator = AIJudgeLoopEvaluator(_FakeJudge('hmm not sure'));

      final result = await evaluator.evaluate(_contextWith('partial'));

      expect(result.shouldReinvoke, isTrue);
    });
  });

  group('TodoCompletionLoopEvaluator', () {
    test('throws when no TodoProvider is resolvable', () async {
      final evaluator = TodoCompletionLoopEvaluator();

      expect(
        () => evaluator.evaluate(_contextWith('x')),
        throwsA(isA<StateError>()),
      );
    });

    test('stops when no incomplete todos remain', () async {
      final provider = TodoProvider();
      final session = _TestSession();
      final agent = _ServiceAgent({TodoProvider: provider});
      final evaluator = TodoCompletionLoopEvaluator();

      final result = await evaluator.evaluate(
        LoopContext(agent, session, [_userText('go')], _text('done')),
      );

      expect(result.shouldReinvoke, isFalse);
    });

    test(
      'continues with the remaining todos formatted into feedback',
      () async {
        final provider = TodoProvider();
        final session = _TestSession();
        await _seedTodo(provider, session, id: 1, title: 'task one');
        final agent = _ServiceAgent({TodoProvider: provider});
        final evaluator = TodoCompletionLoopEvaluator();

        final result = await evaluator.evaluate(
          LoopContext(agent, session, [_userText('go')], _text('partial')),
        );

        expect(result.shouldReinvoke, isTrue);
        expect(result.feedback, contains('task one'));
      },
    );

    test('stops when the current mode is not a configured mode', () async {
      final provider = TodoProvider();
      final session = _TestSession();
      await _seedTodo(provider, session, id: 1, title: 'task one');
      final agent = _ServiceAgent({
        TodoProvider: provider,
        AgentModeProvider: AgentModeProvider(),
      });
      final evaluator = TodoCompletionLoopEvaluator(
        options: TodoCompletionLoopEvaluatorOptions()
          ..modes = const ['nonexistent-mode'],
      );

      final result = await evaluator.evaluate(
        LoopContext(agent, session, [_userText('go')], _text('partial')),
      );

      expect(result.shouldReinvoke, isFalse);
    });
  });

  group('BackgroundTaskCompletionLoopEvaluator', () {
    test('throws when no BackgroundAgentsProvider is resolvable', () async {
      final evaluator = BackgroundTaskCompletionLoopEvaluator();

      expect(
        () => evaluator.evaluate(_contextWith('x')),
        throwsA(isA<StateError>()),
      );
    });

    test('stops when no background tasks are running', () async {
      final provider = BackgroundAgentsProvider([_NamedAgent('researcher')]);
      final session = _TestSession();
      final agent = _ServiceAgent({BackgroundAgentsProvider: provider});
      final evaluator = BackgroundTaskCompletionLoopEvaluator();

      final result = await evaluator.evaluate(
        LoopContext(agent, session, [_userText('go')], _text('done')),
      );

      expect(result.shouldReinvoke, isFalse);
    });

    test('continues while background tasks are still running', () async {
      final provider = BackgroundAgentsProvider([_NamedAgent('researcher')]);
      final session = _TestSession();
      _seedBackgroundTasks(session, [
        BackgroundTaskInfo()
          ..id = 7
          ..agentName = 'researcher'
          ..description = 'dig into the archives'
          ..status = BackgroundTaskStatus.running,
        BackgroundTaskInfo()
          ..id = 8
          ..agentName = 'researcher'
          ..description = 'already done'
          ..status = BackgroundTaskStatus.completed,
      ]);
      final agent = _ServiceAgent({BackgroundAgentsProvider: provider});
      final evaluator = BackgroundTaskCompletionLoopEvaluator();

      final result = await evaluator.evaluate(
        LoopContext(agent, session, [_userText('go')], _text('partial')),
      );

      expect(result.shouldReinvoke, isTrue);
      expect(result.feedback, contains('1 background task(s)'));
      expect(
        result.feedback,
        contains('- #7 (researcher): dig into the archives'),
      );
      expect(result.feedback, isNot(contains('already done')));
    });
  });
}

void _seedBackgroundTasks(
  AgentSession session,
  List<BackgroundTaskInfo> tasks,
) {
  session.stateBag.setValue<BackgroundAgentState>(
    'BackgroundAgentsProvider',
    BackgroundAgentState()..tasks = tasks,
  );
}

Future<void> _seedTodo(
  TodoProvider provider,
  AgentSession session, {
  required int id,
  required String title,
}) async {
  // Initialize the provider's state in the session, then seed an item.
  await provider.getAllTodos(session);
  final state = session.stateBag.getValue<TodoState>(provider.stateKeys[0])!;
  state.items.add(
    TodoItem()
      ..id = id
      ..title = title,
  );
}

LoopContext _contextWith(String lastResponseText) => LoopContext(
  _ScriptedAgent(),
  _TestSession(),
  [_userText('go')],
  _text(lastResponseText),
);

ChatMessage _userText(String text) => ChatMessage.fromText(ChatRole.user, text);

AgentResponse _text(String text) =>
    AgentResponse(message: ChatMessage.fromText(ChatRole.assistant, text));

class _StopEvaluator extends LoopEvaluator {
  @override
  Future<LoopEvaluation> evaluate(
    LoopContext context, {
    CancellationToken? cancellationToken,
  }) async => LoopEvaluation.stop();
}

class _AlwaysProceed extends LoopEvaluator {
  int calls = 0;

  @override
  Future<LoopEvaluation> evaluate(
    LoopContext context, {
    CancellationToken? cancellationToken,
  }) async {
    calls++;
    return LoopEvaluation.proceed('again');
  }
}

class _QueueEvaluator extends LoopEvaluator {
  _QueueEvaluator(this._queue);

  final List<LoopEvaluation> _queue;
  int calls = 0;

  @override
  Future<LoopEvaluation> evaluate(
    LoopContext context, {
    CancellationToken? cancellationToken,
  }) async {
    calls++;
    if (_queue.isEmpty) {
      return LoopEvaluation.stop();
    }
    return _queue.removeAt(0);
  }
}

class _ScriptedAgent extends AIAgent {
  _ScriptedAgent({this.responses = const [], this.streams = const []});

  final List<AgentResponse> responses;
  final List<List<AgentResponseUpdate>> streams;
  final List<List<ChatMessage>> capturedRuns = [];

  int runCount = 0;
  int createSessionCount = 0;
  int _responseIndex = 0;
  int _streamIndex = 0;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async {
    createSessionCount++;
    return _TestSession();
  }

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
  }) async => 'snapshot';

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    capturedRuns.add(List<ChatMessage>.of(messages));
    runCount++;
    final response = _responseIndex < responses.length
        ? responses[_responseIndex]
        : _text('ok');
    _responseIndex++;
    return response;
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    capturedRuns.add(List<ChatMessage>.of(messages));
    runCount++;
    final updates = _streamIndex < streams.length
        ? streams[_streamIndex]
        : <AgentResponseUpdate>[];
    _streamIndex++;
    for (final update in updates) {
      yield update;
    }
  }
}

class _ServiceAgent extends _ScriptedAgent {
  _ServiceAgent(this._services);

  final Map<Type, Object> _services;

  @override
  Object? getService(Type serviceType, {Object? serviceKey}) =>
      _services[serviceType] ??
      super.getService(serviceType, serviceKey: serviceKey);
}

class _NamedAgent extends _ScriptedAgent {
  _NamedAgent(this._name);

  final String _name;

  @override
  String? get name => _name;
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

class _FunctionToolCall extends ToolCallContent implements FunctionCallContent {
  _FunctionToolCall({required super.callId, required this.name});

  @override
  final String name;

  @override
  final Map<String, Object?>? arguments = null;

  @override
  Exception? exception;
}

class _FakeJudge implements ChatClient {
  _FakeJudge(this._responseText);

  final String _responseText;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async => ChatResponse.fromMessage(
    ChatMessage.fromText(ChatRole.assistant, _responseText),
  );

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {}

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}
}
