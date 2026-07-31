import 'dart:async';

import 'package:extensions/system.dart';

import '../checkpoint_info.dart';
import '../checkpoint_manager.dart';
import '../checkpointing/checkpoint.dart';
import '../checkpointing/checkpoint_manager_impl.dart';
import '../edge_id.dart';
import '../execution/concurrent_event_sink.dart';
import '../execution/execution_mode.dart';
import '../execution/message_envelope.dart';
import '../run.dart';
import '../run_status.dart';
import '../streaming_run.dart';
import '../workflow.dart';
import '../workflow_error_event.dart';
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

  /// Starts [workflow] and returns a live [StreamingRun].
  ///
  /// The workflow is driven in the background; the returned run's
  /// [StreamingRun.watchStreamAsync] observes events while executors are
  /// still running. In [ExecutionMode.offThread] (the default) every event
  /// streams out the moment it is created — including outputs yielded
  /// mid-invocation, such as streamed agent updates. In
  /// [ExecutionMode.lockstep] events are batched and published together
  /// after each superstep completes. [StreamingRun.outgoingEvents] is only
  /// complete once the run has ended; watch the stream rather than reading
  /// it right after this method returns.
  ///
  /// External responses sent via [StreamingRun.sendResponseAsync] (and
  /// messages via [StreamingRun.trySendMessageAsync]) resume the run.
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
    return _openStreamingRun(
      workflow: workflow,
      sessionId: session.sessionId,
      checkpointManager: checkpointManager,
      token: token,
      start: (runner) async {
        if (input != null) {
          runner.context.addExternalMessage(input as Object);
        }
      },
    );
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

  /// Resumes [workflow] from [checkpoint] as a live [StreamingRun].
  ///
  /// Streams with the same semantics as [streamAsync]: the run is driven in
  /// the background and events are observed via
  /// [StreamingRun.watchStreamAsync].
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
    return _openStreamingRun(
      workflow: workflow,
      sessionId: effectiveSessionId,
      checkpointManager: checkpointManager,
      token: token,
      fallbackCheckpoint: checkpoint,
      start: (runner) => _importCheckpointAsync(runner, restored, token),
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  StreamingRun _openStreamingRun({
    required Workflow workflow,
    required String sessionId,
    required CancellationToken token,
    required Future<void> Function(InProcessRunner runner) start,
    CheckpointManager? checkpointManager,
    CheckpointInfo? fallbackCheckpoint,
  }) {
    late final _StreamingRunDriver driver;
    final sink = ConcurrentEventSink()
      ..eventRaised = (_, event) => driver.enqueue(event);

    final runner = InProcessRunner.topLevel(
      workflow: workflow,
      sessionId: sessionId,
      outgoingEvents: sink,
      options: options,
      checkpointManager: checkpointManager,
    );
    final streamingRun = StreamingRun(
      sessionId: sessionId,
      status: RunStatus.running,
      lastCheckpoint: fallbackCheckpoint,
      sendMessageCallback: (message, cancellationToken) async {
        if (message == null) return false;
        runner.context.addExternalMessage(message);
        await driver.pump(cancellationToken);
        return true;
      },
      sendResponseCallback: (response, cancellationToken) async {
        runner.context.addExternalResponse(response);
        await driver.pump(cancellationToken);
      },
      cancelCallback: () => runner.endRunAsync(),
      disposeCallback: () => runner.endRunAsync(),
    );
    driver = _StreamingRunDriver(
      runner: runner,
      run: streamingRun,
      lockstep: options.executionMode == ExecutionMode.lockstep,
    );
    unawaited(
      driver.kickoff(() => start(runner), token).catchError((Object _) {
        // Failures are surfaced on the stream as WorkflowErrorEvents and the
        // run is completed by the driver; nothing is left to propagate here.
      }),
    );
    return streamingRun;
  }

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
    final fanInState = <EdgeId, List<MessageEnvelope>>{
      for (final entry in checkpoint.fanInState.entries)
        EdgeId(entry.key): entry.value
            .map(MessageEnvelope.fromPortable)
            .toList(),
    };
    runner.context.stepTracer.reload(checkpoint.superStep);
    await runner.context.importStateAsync(
      instantiatedExecutors: const [],
      queuedMessages: queuedMessages,
      outstandingRequests: const [],
      fanInState: fanInState,
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

// ── private ──────────────────────────────────────────────────────────────────

/// Drives an [InProcessRunner] in the background and publishes its events to
/// a [StreamingRun] — immediately in off-thread mode, or batched per
/// superstep in lockstep mode.
final class _StreamingRunDriver {
  _StreamingRunDriver({
    required this.runner,
    required this.run,
    required this.lockstep,
  });

  final InProcessRunner runner;
  final StreamingRun run;
  final bool lockstep;
  final List<WorkflowEvent> _buffer = [];
  Future<void>? _active;

  Future<void> enqueue(WorkflowEvent event) async {
    if (lockstep) {
      _buffer.add(event);
    } else {
      _publish(event);
    }
  }

  /// Registers the initial prepare-and-drive pass.
  ///
  /// Runs synchronously up to the first suspension point in [prepare], so
  /// the pass is chained into [_active] before any caller can [pump].
  Future<void> kickoff(
    Future<void> Function() prepare,
    CancellationToken token,
  ) {
    final pass = () async {
      await prepare();
      await _pumpOnce(token);
    }();
    _active = pass;
    return pass;
  }

  /// Runs supersteps until the runner is quiescent, then completes the run's
  /// event stream unless external requests are still outstanding.
  ///
  /// Concurrent calls are serialized: a call made while a drive is in
  /// flight waits for it, then drives again so deliveries queued in the
  /// meantime (external messages and responses) are processed before the
  /// returned future completes.
  Future<void> pump(CancellationToken? cancellationToken) {
    final previous = _active;
    final pass = () async {
      if (previous != null) {
        // Only this pass's own errors belong to this caller.
        try {
          await previous;
        } catch (_) {}
      }
      await _pumpOnce(cancellationToken ?? CancellationToken.none);
    }();
    _active = pass;
    return pass;
  }

  Future<void> _pumpOnce(CancellationToken token) async {
    if (run.isCompleted) return;
    try {
      while (runner.hasUnprocessedMessages) {
        token.throwIfCancellationRequested();
        await runner.runSuperStepAsync(cancellationToken: token);
        _flushBuffer();
      }
    } catch (error) {
      _flushBuffer();
      // Executor failures were already evented by the runner; anything else
      // (for example a response with an unknown requestId) has not been.
      if (!_alreadyEvented(error)) {
        _publish(WorkflowErrorEvent(error));
      }
      await _endAsync();
      rethrow;
    }
    if (!runner.hasUnservicedRequests) {
      await _endAsync();
    }
  }

  bool _alreadyEvented(Object error) => run.outgoingEvents.any(
    (event) => event is WorkflowErrorEvent && identical(event.data, error),
  );

  void _flushBuffer() {
    if (_buffer.isEmpty) return;
    final batch = List<WorkflowEvent>.of(_buffer);
    _buffer.clear();
    batch.forEach(_publish);
  }

  void _publish(WorkflowEvent event) {
    if (!run.isCompleted) {
      run.addEvent(event);
    }
  }

  Future<void> _endAsync() async {
    run.lastCheckpoint =
        runner.context.stepTracer.checkpoint ?? run.lastCheckpoint;
    await runner.endRunAsync();
    if (!run.isCompleted) {
      await run.complete();
    }
  }
}
