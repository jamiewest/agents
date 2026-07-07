import 'dart:async';
import 'dart:convert';

import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/workflows/execution/async_run_handle.dart';
import 'package:agents/src/workflows/magentic_plan_review_request.dart';
import 'package:agents/src/workflows/magentic_progress_ledger.dart';
import 'package:agents/src/workflows/magentic_workflow_builder.dart';
import 'package:agents/src/workflows/request_info_event.dart';
import 'package:agents/src/workflows/run_status.dart';
import 'package:agents/src/workflows/specialized/magentic/chat_message_extensions.dart';
import 'package:agents/src/workflows/specialized/magentic/magentic_orchestrator.dart';
import 'package:agents/src/workflows/workflow.dart';
import 'package:agents/src/workflows/workflow_event.dart';
import 'package:agents/src/workflows/workflow_output_event.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('MagenticProgressLedger', () {
    test('updates state when all required slots are answered', () {
      // Arrange
      final ledger = MagenticProgressLedger('Worker, Writer');

      // Act
      final updated = ledger.tryUpdateState(
        _ledgerAnswers(satisfied: false, nextSpeaker: 'Writer'),
      );

      // Assert
      expect(updated, isTrue);
      expect(ledger.isStarted, isTrue);
      expect(ledger.isRequestSatisfied, isFalse);
      expect(ledger.isProgressBeingMade, isTrue);
      expect(ledger.nextSpeaker, 'Writer');
      expect(ledger.instructionOrQuestion, 'Do the work');
    });

    test('rejects an answer set missing a required slot', () {
      // Arrange
      final ledger = MagenticProgressLedger('Worker');
      final answers = _ledgerAnswers(satisfied: true)..remove('next_speaker');

      // Act
      final updated = ledger.tryUpdateState(answers);

      // Assert
      expect(updated, isFalse);
      expect(ledger.isStarted, isFalse);
    });

    test('formats questions and a schema for every slot', () {
      // Arrange
      final ledger = MagenticProgressLedger('Worker');

      // Act
      final (questions, schema) = ledger.formatQuestions();

      // Assert
      for (final slot in ledger.slots) {
        expect(schema, contains('"${slot.key}"'));
      }
      expect(questions, contains('Who should speak next'));
      expect(schema, contains('boolean'));
      expect(schema, contains('string'));
    });
  });

  group('extractJsonFromText', () {
    test('extracts a fenced json block', () {
      // Arrange
      const text = 'noise\n```json\n{"a": 1}\n```\nmore';

      // Act
      final json = extractJsonFromText(text);

      // Assert
      expect(json, {'a': 1});
    });

    test('extracts a brace-balanced object ignoring strings', () {
      // Arrange
      const text = 'prefix {"a": "}", "b": {"c": 2}} suffix';

      // Act
      final json = extractJsonFromText(text);

      // Assert
      expect(json['a'], '}');
      expect((json['b'] as Map)['c'], 2);
    });

    test('throws when no object is present', () {
      expect(() => extractJsonFromText('no json here'), throwsStateError);
    });
  });

  group('MagenticWorkflowBuilder', () {
    test('throws when built without participants', () {
      // Arrange
      final builder = MagenticWorkflowBuilder(_managerAgent());

      // Act / Assert
      expect(builder.build, throwsStateError);
    });

    test('builds a workflow with the orchestrator output and review port', () {
      // Arrange
      final builder = MagenticWorkflowBuilder(_managerAgent())
        ..addParticipants([_workerAgent()]);

      // Act
      final workflow = builder.build();

      // Assert
      expect(
        workflow.reflectOutputExecutors(),
        contains(MagenticOrchestrator.defaultId),
      );
      expect(
        workflow.reflectPorts().map((p) => p.id),
        contains(MagenticWorkflowBuilder.planReviewPortId),
      );
    });
  });

  group('Magentic orchestration', () {
    test('runs autonomously when plan sign-off is disabled', () async {
      // Arrange
      final manager = _managerAgent(satisfyOnProgressCall: 1);
      final workflow =
          (MagenticWorkflowBuilder(manager)
                ..addParticipants([_workerAgent()])
                ..requirePlanSignoff(false))
              .build();

      // Act
      final result = await _run(workflow, 'Solve the task');

      // Assert
      expect(result.status, RunStatus.ended);
      expect(result.planCreatedEvents, hasLength(1));
      expect(result.finalAnswerText, contains('FINAL'));
    });

    test('pauses for plan sign-off and completes once approved', () async {
      // Arrange
      final manager = _managerAgent(satisfyOnProgressCall: 2);
      final worker = _workerAgent();
      final workflow = (MagenticWorkflowBuilder(
        manager,
      )..addParticipants([worker])).build();

      // Act
      final handle = AsyncRunHandle.open<Object?>(
        workflow,
        input: 'Solve the task',
      );
      final events = <WorkflowEvent>[];
      final sub = handle.events.listen(events.add);

      await _settle(handle);
      expect(await handle.getStatusAsync(), RunStatus.pendingRequests);

      final reviewRequest = _planReviewRequest(events);
      await handle.sendResponseAsync(
        _requestEvent(events).request.createResponse(reviewRequest.approve()),
      );
      await _settle(handle);
      await sub.cancel();

      // Assert
      expect(await handle.getStatusAsync(), RunStatus.ended);
      expect(_dataOf<MagenticPlanCreatedEvent>(events), hasLength(1));
      expect(worker.runCount, greaterThanOrEqualTo(1));
      expect(_finalAnswerText(events), contains('FINAL'));

      // Each round emits a snapshot, so per-round state is preserved even
      // though multiple rounds run within a single super-step.
      final ledgers = _dataOf<MagenticProgressLedgerUpdatedEvent>(
        events,
      ).map((e) => e.progressLedger.isRequestSatisfied).toList();
      expect(ledgers, [false, true]);
    });

    test('replans after a revision then completes once approved', () async {
      // Arrange
      final manager = _managerAgent(satisfyOnProgressCall: 1);
      final workflow = (MagenticWorkflowBuilder(
        manager,
      )..addParticipants([_workerAgent()])).build();

      // Act
      final handle = AsyncRunHandle.open<Object?>(
        workflow,
        input: 'Solve the task',
      );
      final events = <WorkflowEvent>[];
      final sub = handle.events.listen(events.add);

      await _settle(handle);
      final firstRequest = _requestEvent(events);
      final firstReview =
          firstRequest.request.request as MagenticPlanReviewRequest;
      await handle.sendResponseAsync(
        firstRequest.request.createResponse(
          firstReview.reviseText('Please add more detail.'),
        ),
      );
      await _settle(handle);

      // After a revision a new sign-off request is posted; approve it.
      final secondRequest = _requestEvent(events);
      final secondReview =
          secondRequest.request.request as MagenticPlanReviewRequest;
      await handle.sendResponseAsync(
        secondRequest.request.createResponse(secondReview.approve()),
      );
      await _settle(handle);
      await sub.cancel();

      // Assert
      expect(await handle.getStatusAsync(), RunStatus.ended);
      expect(_dataOf<MagenticReplannedEvent>(events), isNotEmpty);
      expect(_finalAnswerText(events), contains('FINAL'));
    });
  });
}

// ── helpers ──────────────────────────────────────────────────────────────

Future<void> _settle(AsyncRunHandle<Object?> handle) async {
  for (var i = 0; i < 1000; i++) {
    final status = await handle.getStatusAsync();
    if (status == RunStatus.pendingRequests || status == RunStatus.ended) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('Workflow did not settle.');
}

RequestInfoEvent _requestEvent(List<WorkflowEvent> events) =>
    events.whereType<RequestInfoEvent>().last;

MagenticPlanReviewRequest _planReviewRequest(List<WorkflowEvent> events) =>
    _requestEvent(events).request.request as MagenticPlanReviewRequest;

Iterable<T> _dataOf<T>(List<WorkflowEvent> events) =>
    events.whereType<WorkflowOutputEvent>().map((e) => e.data).whereType<T>();

String _finalAnswerText(List<WorkflowEvent> events) {
  final answers = _dataOf<List<ChatMessage>>(events).toList();
  expect(answers, isNotEmpty);
  return answers.last.map((m) => m.text).join();
}

class _RunResult {
  _RunResult(this.status, this.events);
  final RunStatus status;
  final List<WorkflowEvent> events;

  Iterable<MagenticPlanCreatedEvent> get planCreatedEvents =>
      _dataOf<MagenticPlanCreatedEvent>(events);

  String get finalAnswerText => _finalAnswerText(events);
}

Future<_RunResult> _run(Workflow workflow, String input) async {
  final handle = AsyncRunHandle.open<Object?>(workflow, input: input);
  final events = <WorkflowEvent>[];
  final sub = handle.events.listen(events.add);
  await _settle(handle);
  await sub.cancel();
  return _RunResult(await handle.getStatusAsync(), events);
}

Map<String, Object?> _ledgerAnswers({
  required bool satisfied,
  String nextSpeaker = 'Worker',
  String instruction = 'Do the work',
}) => <String, Object?>{
  'is_request_satisfied': {'answer': satisfied, 'reason': 'r'},
  'is_in_loop': {'answer': false, 'reason': 'r'},
  'is_progress_being_made': {'answer': true, 'reason': 'r'},
  'next_speaker': {'answer': nextSpeaker, 'reason': 'r'},
  'instruction_or_question': {'answer': instruction, 'reason': 'r'},
};

_ScriptedAgent _managerAgent({int satisfyOnProgressCall = 1}) {
  var progressCalls = 0;
  return _ScriptedAgent(
    name: 'Manager',
    description: 'Plans and coordinates the team.',
    onRun: (messages, options) {
      final text = messages.last.text;
      if (text.contains('pure JSON format')) {
        progressCalls++;
        final satisfied = progressCalls >= satisfyOnProgressCall;
        return _assistant(jsonEncode(_ledgerAnswers(satisfied: satisfied)));
      }
      if (text.contains('provide the final answer')) {
        return _assistant('FINAL: the task is complete.');
      }
      if (text.contains('pre-survey') || text.contains('fact sheet')) {
        return _assistant('FACTS');
      }
      return _assistant('PLAN');
    },
  );
}

_ScriptedAgent _workerAgent() => _ScriptedAgent(
  name: 'Worker',
  description: 'Performs assigned work.',
  onRun: (messages, options) => _assistant('worker completed the step'),
);

AgentResponse _assistant(String text) =>
    AgentResponse(messages: [ChatMessage.fromText(ChatRole.assistant, text)]);

class _ScriptedAgent extends AIAgent {
  _ScriptedAgent({String? name, String? description, required this.onRun})
    : _name = name,
      _description = description;

  final String? _name;
  final String? _description;
  final AgentResponse Function(
    List<ChatMessage> messages,
    AgentRunOptions? options,
  )
  onRun;

  int runCount = 0;

  @override
  String? get name => _name;

  @override
  String? get description => _description;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _FakeSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => null;

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _FakeSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    runCount++;
    return onRun(List<ChatMessage>.of(messages), options);
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final response = await runCore(
      messages,
      session: session,
      options: options,
      cancellationToken: cancellationToken,
    );
    for (final update in response.toAgentResponseUpdates()) {
      yield update;
    }
  }
}

class _FakeSession extends AgentSession {
  _FakeSession() : super(AgentSessionStateBag(null));
}
