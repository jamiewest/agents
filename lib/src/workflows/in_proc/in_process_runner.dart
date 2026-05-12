import 'package:extensions/system.dart';

import '../checkpoint_info.dart';
import '../checkpoint_manager.dart';
import '../checkpointing/checkpoint.dart';
import '../checkpointing/workflow_info.dart';
import '../execution/concurrent_event_sink.dart';
import '../execution/super_step_join_context.dart';
import '../executor_completed_event.dart';
import '../executor_failed_event.dart';
import '../executor_invoked_event.dart';
import '../workflow.dart';
import '../workflow_error_event.dart';
import '../workflow_event.dart';
import 'in_proc_step_tracer.dart';
import 'in_process_execution_options.dart';
import 'in_process_runner_context.dart';

/// In-process implementation of [ISuperStepRunner].
///
/// Drives one superstep per [runSuperStepAsync] call: drains the message
/// queue, invokes executors, routes their return values through edges,
/// publishes state, and optionally creates a checkpoint.
final class InProcessRunner implements ISuperStepRunner {
  InProcessRunner._({
    required String sessionId,
    required Workflow workflow,
    required InProcessRunnerContext context,
    CheckpointManager? checkpointManager,
  }) : _sessionId = sessionId,
       _workflow = workflow,
       _context = context,
       _checkpointManager = checkpointManager;

  final String _sessionId;
  final Workflow _workflow;
  final InProcessRunnerContext _context;
  final CheckpointManager? _checkpointManager;

  // ── factory constructors ─────────────────────────────────────────────────

  /// Creates a top-level runner for [workflow].
  factory InProcessRunner.topLevel({
    required Workflow workflow,
    required String sessionId,
    required IEventSink outgoingEvents,
    InProcessExecutionOptions options = const InProcessExecutionOptions(),
    CheckpointManager? checkpointManager,
  }) {
    final tracer = InProcStepTracer();
    final context = InProcessRunnerContext(
      workflow: workflow,
      sessionId: sessionId,
      checkpointingEnabled: checkpointManager != null,
      outgoingEvents: outgoingEvents,
      stepTracer: tracer,
      enableConcurrentRuns: options.allowSharedWorkflow,
    );
    return InProcessRunner._(
      sessionId: sessionId,
      workflow: workflow,
      context: context,
      checkpointManager: checkpointManager,
    );
  }

  /// Creates a sub-workflow runner that forwards events to [parentContext].
  factory InProcessRunner.subWorkflow({
    required Workflow workflow,
    required String sessionId,
    required SuperStepJoinContext parentContext,
    CheckpointManager? checkpointManager,
  }) {
    final tracer = InProcStepTracer();
    final eventSink = _ParentForwardingEventSink(parentContext);
    final context = InProcessRunnerContext(
      workflow: workflow,
      sessionId: sessionId,
      checkpointingEnabled: parentContext.checkpointingEnabled,
      outgoingEvents: eventSink,
      stepTracer: tracer,
      enableConcurrentRuns: parentContext.concurrentRunsEnabled,
    );
    return InProcessRunner._(
      sessionId: sessionId,
      workflow: workflow,
      context: context,
      checkpointManager: checkpointManager,
    );
  }

  // ── ISuperStepRunner ─────────────────────────────────────────────────────

  @override
  String get sessionId => _sessionId;

  @override
  bool get hasUnprocessedMessages => _context.nextStepHasActions;

  @override
  bool get hasUnservicedRequests => _context.hasUnservicedRequests;

  /// Gets the runner context (used by the execution environment).
  InProcessRunnerContext get context => _context;

  @override
  Future<bool> runSuperStepAsync({
    CancellationToken? cancellationToken,
  }) async {
    if (!_context.nextStepHasActions) return false;

    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();

    final step = await _context.advanceAsync();

    final startEvent = _context.stepTracer.advance(
      step.map((k, v) => MapEntry(k, v.map((e) => e.message).toList())),
    );
    await _context.forwardWorkflowEventAsync(
      startEvent,
      cancellationToken: token,
    );

    var didWork = step.isNotEmpty;

    for (final entry in step.entries) {
      final executorId = entry.key;
      final envelopes = entry.value;

      final executor = await _context.ensureExecutorAsync(
        executorId,
        tracer: _context.stepTracer,
        cancellationToken: token,
      );
      _context.stepTracer.traceActivated(executorId);

      for (final envelope in envelopes) {
        token.throwIfCancellationRequested();
        final boundCtx = _context.bindWorkflowContext(executorId);

        await _context.forwardWorkflowEventAsync(
          ExecutorInvokedEvent(
            executorId: executorId,
            data: envelope.message,
          ),
          cancellationToken: token,
        );

        try {
          final output = await executor.handle(
            envelope.message,
            boundCtx,
            cancellationToken: token,
          );
          if (output != null) {
            final nonNull = output as Object;
            await _context.yieldOutputAsync(
              executorId,
              nonNull,
              cancellationToken: token,
            );
            await _context.sendMessageAsync(
              executorId,
              nonNull,
              cancellationToken: token,
            );
          }
          await _context.forwardWorkflowEventAsync(
            ExecutorCompletedEvent(executorId: executorId, data: output),
            cancellationToken: token,
          );
          didWork = true;
        } catch (error) {
          await _context.forwardWorkflowEventAsync(
            ExecutorFailedEvent(executorId: executorId, error: error),
            cancellationToken: token,
          );
          await _context.forwardWorkflowEventAsync(
            WorkflowErrorEvent(error),
            cancellationToken: token,
          );
          rethrow;
        }
      }
    }

    for (final subRunner in _context.joinedSubworkflowRunners.toList()) {
      if (subRunner.hasUnprocessedMessages) {
        final subDidWork = await subRunner.runSuperStepAsync(
          cancellationToken: cancellationToken,
        );
        didWork = didWork || subDidWork;
      }
    }

    _context.stateManager.publishUpdates(_context.stepTracer);

    if (_context.checkpointingEnabled && _checkpointManager != null) {
      await _saveCheckpointAsync(token);
    }

    final completedEvent = _context.stepTracer.complete(
      nextStepHasActions: _context.nextStepHasActions,
      hasPendingRequests: _context.hasUnservicedRequests,
    );
    await _context.forwardWorkflowEventAsync(
      completedEvent,
      cancellationToken: token,
    );

    return didWork;
  }

  /// Ends the run and releases workflow ownership.
  Future<void> endRunAsync() => _context.endRunAsync();

  // ── checkpoint ───────────────────────────────────────────────────────────

  Future<void> _saveCheckpointAsync(CancellationToken token) async {
    token.throwIfCancellationRequested();
    final manager = _checkpointManager!;
    final exported = _context.exportState();
    final stepNumber = _context.stepTracer.stepNumber;
    final checkpoint = Checkpoint(
      info: CheckpointInfo('$_sessionId-step-$stepNumber'),
      sessionId: _sessionId,
      superStep: stepNumber,
      workflow: WorkflowInfo.fromWorkflow(_workflow),
      pendingMessages: exported.queuedMessages.values
          .expand((envelopes) => envelopes)
          .map((e) => e.toPortable()),
    );
    final info = await manager.saveCheckpointAsync(checkpoint);
    _context.stepTracer.traceCheckpointCreated(info);
  }
}

// ── private ──────────────────────────────────────────────────────────────────

class _ParentForwardingEventSink implements IEventSink {
  _ParentForwardingEventSink(this._parent);
  final SuperStepJoinContext _parent;

  @override
  Future<void> enqueue(WorkflowEvent workflowEvent) =>
      _parent.forwardWorkflowEventAsync(workflowEvent);
}
