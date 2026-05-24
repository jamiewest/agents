import 'dart:async';

import 'package:extensions/system.dart';

import 'checkpoint_info.dart';
import 'external_response.dart';
import 'request_halt_event.dart';
import 'request_info_event.dart';
import 'run_status.dart';
import 'workflow_event.dart';
import 'workflow_session.dart';

/// A workflow run instance supporting streaming workflow events.
class StreamingRun {
  /// Creates a streaming run.
  StreamingRun({
    required this.sessionId,
    RunStatus status = RunStatus.notStarted,
    this.lastCheckpoint,
    Future<bool> Function(Object? message, CancellationToken cancellationToken)?
    sendMessageCallback,
    Future<void> Function(
      ExternalResponse<dynamic> response,
      CancellationToken cancellationToken,
    )?
    sendResponseCallback,
    Future<void> Function()? cancelCallback,
    Future<void> Function()? disposeCallback,
  }) : _status = status,
       _sendMessageCallback = sendMessageCallback,
       _sendResponseCallback = sendResponseCallback,
       _cancelCallback = cancelCallback,
       _disposeCallback = disposeCallback;

  /// Creates a streaming run for [session].
  StreamingRun.forSession(
    WorkflowSession session, {
    RunStatus status = RunStatus.notStarted,
    CheckpointInfo? lastCheckpoint,
  }) : this(
         sessionId: session.sessionId,
         status: status,
         lastCheckpoint: lastCheckpoint,
       );

  final StreamController<WorkflowEvent> _events =
      StreamController<WorkflowEvent>.broadcast();
  final List<WorkflowEvent> _outgoingEvents = <WorkflowEvent>[];
  RunStatus _status;
  bool _disposed = false;

  final Future<bool> Function(
    Object? message,
    CancellationToken cancellationToken,
  )?
  _sendMessageCallback;
  final Future<void> Function(
    ExternalResponse<dynamic> response,
    CancellationToken cancellationToken,
  )?
  _sendResponseCallback;
  final Future<void> Function()? _cancelCallback;
  final Future<void> Function()? _disposeCallback;

  /// Gets a unique identifier for the session.
  final String sessionId;

  /// Gets the most recent checkpoint information.
  CheckpointInfo? lastCheckpoint;

  /// Gets all events emitted by the workflow.
  List<WorkflowEvent> get outgoingEvents =>
      List<WorkflowEvent>.unmodifiable(_outgoingEvents);

  /// Adds an emitted workflow event and publishes it to watchers.
  void addEvent(WorkflowEvent event) {
    _throwIfDisposed();
    _outgoingEvents.add(event);
    if (event is RequestInfoEvent) {
      _status = RunStatus.pendingRequests;
    } else if (event is RequestHaltEvent) {
      _status = RunStatus.ended;
    }
    _events.add(event);
  }

  /// Completes the event stream.
  Future<void> complete() async {
    if (_status != RunStatus.ended) {
      _status = RunStatus.ended;
    }
    await _events.close();
  }

  /// Asynchronously streams workflow events as they occur.
  Stream<WorkflowEvent> watchStreamAsync({
    CancellationToken? cancellationToken,
  }) async* {
    cancellationToken?.throwIfCancellationRequested();
    yield* _events.stream;
  }

  /// Attempts to send [message] to the workflow.
  Future<bool> trySendMessageAsync<TMessage>(
    TMessage message, {
    CancellationToken? cancellationToken,
  }) async {
    _throwIfDisposed();
    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();
    if (_status == RunStatus.ended) {
      return false;
    }
    _status = RunStatus.running;
    if (_sendMessageCallback == null) {
      return true;
    }
    final sendMessageCallback = _sendMessageCallback;
    return sendMessageCallback(message, token);
  }

  /// Sends an external [response] to the workflow.
  Future<void> sendResponseAsync(
    ExternalResponse<dynamic> response, {
    CancellationToken? cancellationToken,
  }) async {
    _throwIfDisposed();
    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();
    _status = RunStatus.running;
    final sendResponseCallback = _sendResponseCallback;
    if (sendResponseCallback != null) {
      await sendResponseCallback(response, token);
    }
  }

  /// Attempts to cancel the streaming run.
  Future<void> cancelRunAsync() async {
    _throwIfDisposed();
    _status = RunStatus.ended;
    final cancelCallback = _cancelCallback;
    if (cancelCallback != null) {
      await cancelCallback();
    }
    await complete();
  }

  /// Gets the current execution status of the workflow run.
  Future<RunStatus> getStatusAsync({
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    return _status;
  }

  /// Disposes this streaming run.
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
    if (!_events.isClosed) {
      await _events.close();
    }
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError('StreamingRun "$sessionId" has been disposed.');
    }
  }
}
