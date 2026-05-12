import 'package:extensions/system.dart';

import '../checkpoint_info.dart';
import '../checkpoint_manager.dart';
import '../checkpointing/checkpoint.dart';
import '../checkpointing/checkpoint_manager_impl.dart';
import '../execution/concurrent_event_sink.dart';
import '../execution/message_envelope.dart';
import '../run.dart';
import '../run_status.dart';
import '../streaming_run.dart';
import '../workflow.dart';
import '../workflow_event.dart';
import '../workflow_execution_environment.dart';
import '../workflow_session.dart';
import 'in_process_execution_options.dart';
import 'in_process_runner.dart';

/// In-process execution environment that uses [InProcessRunner].
///
/// Supports state management, sub-workflow embedding, and checkpoint-based
/// resume. Drop-in replacement for the legacy [InProcessExecutionEnvironment]
/// when the richer execution model is needed.
class InProcExecutionEnvironment implements WorkflowExecutionEnvironment {
  /// Creates an in-proc execution environment.
  const InProcExecutionEnvironment({
    this.options = const InProcessExecutionOptions(),
  });

  /// Execution options applied to every run.
  final InProcessExecutionOptions options;

  @override
  Future<Run> runAsync<TInput>(
    Workflow workflow,
    TInput input, {
    CheckpointManager? checkpointManager,
    String? sessionId,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();
    final session = WorkflowSession(workflow: workflow, sessionId: sessionId);
    final events = <WorkflowEvent>[];
    final sink = ConcurrentEventSink()
      ..eventRaised = (_, event) async => events.add(event);

    final runner = InProcessRunner.topLevel(
      workflow: workflow,
      sessionId: session.sessionId,
      outgoingEvents: sink,
      options: options,
      checkpointManager: checkpointManager,
    );
    runner.context.addExternalMessage(input as Object);

    final status = await _driveAsync(runner, token);
    await runner.endRunAsync();

    return Run(
      sessionId: session.sessionId,
      status: status,
      outgoingEvents: events,
      lastCheckpoint: _lastCheckpoint(runner),
    );
  }

  @override
  Future<StreamingRun> streamAsync<TInput>(
    Workflow workflow, {
    TInput? input,
    CheckpointManager? checkpointManager,
    String? sessionId,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();
    final session = WorkflowSession(workflow: workflow, sessionId: sessionId);
    final events = <WorkflowEvent>[];
    final sink = ConcurrentEventSink()
      ..eventRaised = (_, event) async => events.add(event);

    final runner = InProcessRunner.topLevel(
      workflow: workflow,
      sessionId: session.sessionId,
      outgoingEvents: sink,
      options: options,
      checkpointManager: checkpointManager,
    );
    if (input != null) {
      runner.context.addExternalMessage(input as Object);
    }

    final status = await _driveAsync(runner, token);
    await runner.endRunAsync();

    final streamingRun = StreamingRun(
      sessionId: session.sessionId,
      status: status,
      lastCheckpoint: _lastCheckpoint(runner),
    );
    for (final event in events) {
      streamingRun.addEvent(event);
    }
    if (status == RunStatus.ended) {
      await streamingRun.complete();
    }
    return streamingRun;
  }

  @override
  Future<StreamingRun> openStreamAsync(
    Workflow workflow, {
    String? sessionId,
    CancellationToken? cancellationToken,
  }) => streamAsync<Object?>(
    workflow,
    sessionId: sessionId,
    cancellationToken: cancellationToken,
  );

  @override
  Future<Run> resumeAsync(
    Workflow workflow,
    CheckpointInfo checkpoint,
    CheckpointManager checkpointManager, {
    String? sessionId,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();
    final restored = await _restoreCheckpoint(checkpointManager, checkpoint);
    final effectiveSessionId = sessionId ?? restored.sessionId;
    final events = <WorkflowEvent>[];
    final sink = ConcurrentEventSink()
      ..eventRaised = (_, event) async => events.add(event);

    final runner = InProcessRunner.topLevel(
      workflow: workflow,
      sessionId: effectiveSessionId,
      outgoingEvents: sink,
      options: options,
      checkpointManager: checkpointManager,
    );
    await _importCheckpointAsync(runner, restored, token);

    final status = await _driveAsync(runner, token);
    await runner.endRunAsync();

    return Run(
      sessionId: effectiveSessionId,
      status: status,
      outgoingEvents: events,
      lastCheckpoint: _lastCheckpoint(runner) ?? checkpoint,
    );
  }

  @override
  Future<StreamingRun> resumeStreamAsync(
    Workflow workflow,
    CheckpointInfo checkpoint,
    CheckpointManager checkpointManager, {
    String? sessionId,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();
    final restored = await _restoreCheckpoint(checkpointManager, checkpoint);
    final effectiveSessionId = sessionId ?? restored.sessionId;
    final events = <WorkflowEvent>[];
    final sink = ConcurrentEventSink()
      ..eventRaised = (_, event) async => events.add(event);

    final runner = InProcessRunner.topLevel(
      workflow: workflow,
      sessionId: effectiveSessionId,
      outgoingEvents: sink,
      options: options,
      checkpointManager: checkpointManager,
    );
    await _importCheckpointAsync(runner, restored, token);

    final status = await _driveAsync(runner, token);
    await runner.endRunAsync();

    final streamingRun = StreamingRun(
      sessionId: effectiveSessionId,
      status: status,
      lastCheckpoint: _lastCheckpoint(runner) ?? checkpoint,
    );
    for (final event in events) {
      streamingRun.addEvent(event);
    }
    if (status == RunStatus.ended) {
      await streamingRun.complete();
    }
    return streamingRun;
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  Future<RunStatus> _driveAsync(
    InProcessRunner runner,
    CancellationToken token,
  ) async {
    while (runner.hasUnprocessedMessages) {
      token.throwIfCancellationRequested();
      await runner.runSuperStepAsync(cancellationToken: token);
    }
    return runner.hasUnservicedRequests
        ? RunStatus.pendingRequests
        : RunStatus.ended;
  }

  Future<void> _importCheckpointAsync(
    InProcessRunner runner,
    Checkpoint checkpoint,
    CancellationToken token,
  ) async {
    final queuedMessages = <String, List<MessageEnvelope>>{};
    for (final portable in checkpoint.pendingMessages) {
      final envelope = MessageEnvelope.fromPortable(portable);
      (queuedMessages[envelope.targetExecutorId] ??= []).add(envelope);
    }
    runner.context.stepTracer.reload(checkpoint.superStep);
    await runner.context.importStateAsync(
      instantiatedExecutors: const [],
      queuedMessages: queuedMessages,
      outstandingRequests: const [],
      cancellationToken: token,
    );
  }

  CheckpointInfo? _lastCheckpoint(InProcessRunner runner) =>
      runner.context.stepTracer.checkpoint;

  Future<Checkpoint> _restoreCheckpoint(
    CheckpointManager checkpointManager,
    CheckpointInfo checkpoint,
  ) async {
    if (checkpointManager is CheckpointManagerImpl) {
      final restored = await checkpointManager.restoreTypedCheckpointAsync(
        checkpoint,
      );
      if (restored == null) {
        throw StateError(
          'Checkpoint "${checkpoint.checkpointId}" was not found.',
        );
      }
      return restored;
    }
    final restored = await checkpointManager.restoreCheckpointAsync(checkpoint);
    if (restored is Checkpoint) {
      return restored;
    }
    throw StateError(
      'CheckpointManager did not restore a typed workflow Checkpoint.',
    );
  }
}

/// Default [InProcExecutionEnvironment] instance.
const inProcExecution = InProcExecutionEnvironment();
