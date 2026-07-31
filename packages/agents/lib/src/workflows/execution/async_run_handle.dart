import 'dart:async';

import 'package:extensions/system.dart';

import '../checkpoint_manager.dart';
import '../external_response.dart';
import '../in_proc/in_process_execution_options.dart';
import '../in_proc/in_process_runner.dart';
import '../run_status.dart';
import '../workflow.dart';
import '../workflow_error_event.dart';
import '../workflow_event.dart';
import '../workflow_output_event.dart';
import '../workflow_session.dart';
import 'streaming_run_event_stream.dart';

/// A live, bidirectional handle to an in-process workflow run.
///
/// Maps C#'s [AsyncRunHandle<TOutput>]. Events flow out via [events] /
/// [output]; external input flows in via [sendMessageAsync] and
/// [sendResponseAsync]. The workflow is driven automatically in the
/// background once [startDriving] is called (or immediately when created
/// via [AsyncRunHandle.open]).
final class AsyncRunHandle<TOutput> {
  AsyncRunHandle._({
    required InProcessRunner runner,
    required StreamingRunEventStream eventStream,
    required this.sessionId,
  }) : _runner = runner,
       _eventStream = eventStream;

  final InProcessRunner _runner;
  final StreamingRunEventStream _eventStream;
  RunStatus _status = RunStatus.notStarted;
  Future<void>? _driveTask;

  /// The session identifier for this run.
  final String sessionId;

  // ── factory ──────────────────────────────────────────────────────────────

  /// Opens an [AsyncRunHandle] for [workflow], optionally sending [input].
  ///
  /// The workflow begins driving automatically once the returned handle is
  /// created. Attach a listener to [events] before awaiting the returned
  /// [Future] to avoid missing early events.
  static AsyncRunHandle<TOutput> open<TOutput>(
    Workflow workflow, {
    Object? input,
    String? sessionId,
    InProcessExecutionOptions options = const InProcessExecutionOptions(),
    CheckpointManager? checkpointManager,
  }) {
    final session = WorkflowSession(workflow: workflow, sessionId: sessionId);
    final eventStream = StreamingRunEventStream();
    final runner = InProcessRunner.topLevel(
      workflow: workflow,
      sessionId: session.sessionId,
      outgoingEvents: eventStream,
      options: options,
      checkpointManager: checkpointManager,
    );
    if (input != null) {
      runner.context.addExternalMessage(input);
    }
    final handle = AsyncRunHandle<TOutput>._(
      runner: runner,
      eventStream: eventStream,
      sessionId: session.sessionId,
    );
    scheduleMicrotask(handle._ensureDriving);
    return handle;
  }

  // ── output ────────────────────────────────────────────────────────────────

  /// All [WorkflowEvent]s emitted by the workflow.
  Stream<WorkflowEvent> get events => _eventStream.events;

  /// [TOutput] values extracted from [WorkflowOutputEvent]s.
  Stream<TOutput> get output => events
      .where((e) => e is WorkflowOutputEvent && e.data is TOutput)
      .map((e) => (e as WorkflowOutputEvent).data as TOutput);

  /// The current execution status.
  Future<RunStatus> getStatusAsync({
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    return _status;
  }

  // ── input ─────────────────────────────────────────────────────────────────

  /// Sends an external [message] into the workflow and resumes driving.
  Future<void> sendMessageAsync<T>(
    T message, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    _runner.context.addExternalMessage(message as Object);
    await _ensureDriving();
  }

  /// Delivers an external [response] to the workflow and resumes driving.
  Future<void> sendResponseAsync(
    ExternalResponse<dynamic> response, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    _runner.context.addExternalResponse(response);
    await _ensureDriving();
  }

  // ── drive loop ────────────────────────────────────────────────────────────

  /// Ensures pending work is driven to quiescence.
  ///
  /// Concurrent calls are serialized: a call made while a drive loop is in
  /// flight waits for it and then drives again, so deliveries queued in the
  /// meantime (messages and responses) are processed before the returned
  /// future completes.
  Future<void> _ensureDriving() {
    final previous = _driveTask;
    final pass = () async {
      if (previous != null) {
        // Only this pass's own errors belong to this caller.
        try {
          await previous;
        } catch (_) {}
      }
      await _driveOnce();
    }();
    _driveTask = pass;
    return pass;
  }

  Future<void> _driveOnce() async {
    if (_status == RunStatus.ended) return;
    _status = RunStatus.running;
    try {
      while (_runner.hasUnprocessedMessages) {
        await _runner.runSuperStepAsync();
      }
    } catch (error) {
      // The initial drive runs in a microtask with no awaiting caller; an
      // unraised failure would leave stream observers waiting forever.
      // The event stream is the error channel: report and end the run.
      _status = RunStatus.ended;
      await _eventStream.enqueue(WorkflowErrorEvent(error));
      await _eventStream.completeAsync();
      return;
    }
    _status = _runner.hasUnservicedRequests
        ? RunStatus.pendingRequests
        : RunStatus.ended;
    if (_status == RunStatus.ended) {
      await _runner.endRunAsync();
      await _eventStream.completeAsync();
    }
  }
}
