import 'package:extensions/system.dart';

import 'checkpoint_info.dart';
import 'checkpoint_manager.dart';
import 'checkpointing/checkpoint.dart';
import 'checkpointing/checkpoint_manager_impl.dart';
import 'executor.dart';
import 'execution/edge_map.dart';
import 'execution/message_delivery.dart';
import 'execution/message_envelope.dart';
import 'execution/runner_context.dart';
import 'execution/super_step_runner.dart';
import 'run.dart';
import 'run_status.dart';
import 'streaming_run.dart';
import 'workflow.dart';
import 'workflow_execution_environment.dart';
import 'workflow_session.dart';

/// Executes workflows in the current Dart isolate.
class InProcessExecutionEnvironment implements WorkflowExecutionEnvironment {
  /// Creates an in-process execution environment.
  const InProcessExecutionEnvironment();

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
    final ownerToken = Object();
    workflow.takeOwnership(ownerToken);
    final run = Run(sessionId: session.sessionId, status: RunStatus.running);
    try {
      final context = await _createRunnerContext(workflow);
      final runner = SuperStepRunner(
        context,
        sessionId: session.sessionId,
        checkpointManager: checkpointManager,
      );
      final status = await runner.run(input, cancellationToken: token);
      for (final event in context.events) {
        run.addEvent(event);
      }
      run.lastCheckpoint = runner.lastCheckpoint;
      run.setStatus(status);
      return run;
    } finally {
      await workflow.releaseOwnership(ownerToken, null);
    }
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
    final streamingRun = StreamingRun(
      sessionId: session.sessionId,
      status: RunStatus.running,
    );
    final ownerToken = Object();
    workflow.takeOwnership(ownerToken);
    try {
      final context = await _createRunnerContext(workflow);
      final runner = SuperStepRunner(
        context,
        sessionId: session.sessionId,
        checkpointManager: checkpointManager,
      );
      final status = await runner.run(input, cancellationToken: token);
      for (final event in context.events) {
        streamingRun.addEvent(event);
      }
      streamingRun.lastCheckpoint = runner.lastCheckpoint;
      if (status == RunStatus.ended) {
        await streamingRun.complete();
      }
      return streamingRun;
    } finally {
      await workflow.releaseOwnership(ownerToken, null);
    }
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
    final ownerToken = Object();
    workflow.takeOwnership(ownerToken);
    final run = Run(sessionId: effectiveSessionId, status: RunStatus.running);
    try {
      final context = await _createRunnerContext(workflow);
      final runner = SuperStepRunner(
        context,
        sessionId: effectiveSessionId,
        checkpointManager: checkpointManager,
      );
      final status = await runner.runDeliveries(
        restored.pendingMessages.map(
          (message) => MessageDelivery(MessageEnvelope.fromPortable(message)),
        ),
        initialStepNumber: restored.superStep + 1,
        cancellationToken: token,
      );
      for (final event in context.events) {
        run.addEvent(event);
      }
      run.lastCheckpoint = runner.lastCheckpoint ?? checkpoint;
      run.setStatus(status);
      return run;
    } finally {
      await workflow.releaseOwnership(ownerToken, null);
    }
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
    final ownerToken = Object();
    workflow.takeOwnership(ownerToken);
    final streamingRun = StreamingRun(
      sessionId: effectiveSessionId,
      status: RunStatus.running,
    );
    try {
      final context = await _createRunnerContext(workflow);
      final runner = SuperStepRunner(
        context,
        sessionId: effectiveSessionId,
        checkpointManager: checkpointManager,
      );
      final status = await runner.runDeliveries(
        restored.pendingMessages.map(
          (message) => MessageDelivery(MessageEnvelope.fromPortable(message)),
        ),
        initialStepNumber: restored.superStep + 1,
        cancellationToken: token,
      );
      for (final event in context.events) {
        streamingRun.addEvent(event);
      }
      streamingRun.lastCheckpoint = runner.lastCheckpoint ?? checkpoint;
      if (status == RunStatus.ended) {
        await streamingRun.complete();
      }
      return streamingRun;
    } finally {
      await workflow.releaseOwnership(ownerToken, null);
    }
  }

  Future<RunnerContext> _createRunnerContext(Workflow workflow) async {
    final executors = <String, Executor<dynamic, dynamic>>{};
    for (final binding in workflow.reflectExecutors()) {
      executors[binding.id] = await binding.createInstance();
    }
    return RunnerContext(
      workflow: workflow,
      executors: executors,
      edgeMap: EdgeMap(workflow.reflectEdges()),
      outputExecutorIds: workflow.reflectOutputExecutors(),
    );
  }

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

/// Default in-process workflow execution environment.
const inProcessExecution = InProcessExecutionEnvironment();
