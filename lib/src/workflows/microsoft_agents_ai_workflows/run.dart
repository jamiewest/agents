import 'package:extensions/system.dart';

import 'checkpoint_info.dart';
import 'external_response.dart';
import 'request_halt_event.dart';
import 'request_info_event.dart';
import 'run_status.dart';
import 'workflow_event.dart';
import 'workflow_session.dart';

/// Represents a workflow run that tracks status and emitted events.
class Run {
  /// Creates a workflow run.
  Run({
    required this.sessionId,
    RunStatus status = RunStatus.notStarted,
    Iterable<WorkflowEvent> outgoingEvents = const <WorkflowEvent>[],
    this.lastCheckpoint,
    Future<void> Function(
      Iterable<ExternalResponse<dynamic>> responses,
      CancellationToken cancellationToken,
    )?
    resumeCallback,
    Future<void> Function()? disposeCallback,
  }) : _status = status,
       _resumeCallback = resumeCallback,
       _disposeCallback = disposeCallback {
    for (final event in outgoingEvents) {
      addEvent(event);
    }
  }

  /// Creates a workflow run for [session].
  Run.forSession(
    WorkflowSession session, {
    RunStatus status = RunStatus.notStarted,
    Iterable<WorkflowEvent> outgoingEvents = const <WorkflowEvent>[],
    CheckpointInfo? lastCheckpoint,
  }) : this(
         sessionId: session.sessionId,
         status: status,
         outgoingEvents: outgoingEvents,
         lastCheckpoint: lastCheckpoint,
       );

  final List<WorkflowEvent> _outgoingEvents = <WorkflowEvent>[];
  int _newEventOffset = 0;
  RunStatus _status;
  bool _disposed = false;

  final Future<void> Function(
    Iterable<ExternalResponse<dynamic>> responses,
    CancellationToken cancellationToken,
  )?
  _resumeCallback;
  final Future<void> Function()? _disposeCallback;

  /// Gets a unique identifier for the session.
  final String sessionId;

  /// Gets the most recent checkpoint information.
  CheckpointInfo? lastCheckpoint;

  /// Gets all events emitted by the workflow.
  List<WorkflowEvent> get outgoingEvents =>
      List<WorkflowEvent>.unmodifiable(_outgoingEvents);

  /// Gets all events emitted since the last access to [newEvents].
  List<WorkflowEvent> get newEvents {
    final events = _outgoingEvents.skip(_newEventOffset).toList();
    _newEventOffset = _outgoingEvents.length;
    return events;
  }

  /// Gets the number of events emitted since the last access to [newEvents].
  int get newEventCount => _outgoingEvents.length - _newEventOffset;

  /// Gets whether this run has been disposed.
  bool get isDisposed => _disposed;

  /// Adds an emitted workflow event to this run.
  void addEvent(WorkflowEvent event) {
    _throwIfDisposed();
    _outgoingEvents.add(event);
    if (event is RequestInfoEvent) {
      _status = RunStatus.pendingRequests;
    } else if (event is RequestHaltEvent) {
      _status = RunStatus.ended;
    }
  }

  /// Sets the current status.
  void setStatus(RunStatus status) {
    _throwIfDisposed();
    _status = status;
  }

  /// Gets the current execution status of the workflow run.
  Future<RunStatus> getStatusAsync({
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    return _status;
  }

  /// Resumes execution with external responses.
  Future<void> resumeAsync(
    Iterable<ExternalResponse<dynamic>> responses, {
    CancellationToken? cancellationToken,
  }) async {
    _throwIfDisposed();
    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();
    _status = RunStatus.running;
    final resumeCallback = _resumeCallback;
    if (resumeCallback != null) {
      await resumeCallback(responses, token);
    }
  }

  /// Disposes this run.
  Future<void> disposeAsync() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _status = RunStatus.ended;
    final disposeCallback = _disposeCallback;
    if (disposeCallback != null) {
      await disposeCallback();
    }
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError('Run "$sessionId" has been disposed.');
    }
  }
}
