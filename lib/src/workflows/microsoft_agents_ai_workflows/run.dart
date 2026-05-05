import 'package:extensions/system.dart';
import 'checkpointable_run_base.dart';
import 'execution/async_run_handle.dart';
import 'external_response.dart';
import 'request_info_event.dart';
import 'run_status.dart';
import 'workflow_event.dart';

/// Represents a workflow run that tracks execution status and emitted
/// workflow events, supporting resumption with responses to
/// [RequestInfoEvent].
class Run extends CheckpointableRunBase implements AsyncDisposable {
  Run(AsyncRunHandle runHandle) : _runHandle = runHandle {
  }

  final List<WorkflowEvent> _eventSink = [];

  final AsyncRunHandle _runHandle;

  int _lastBookmark;

  /// Gets all events emitted by the workflow since the last access to
  /// [NewEvents].
  final Iterable<WorkflowEvent> newEvents;

  Future<bool> runToNextHalt({CancellationToken? cancellationToken}) async {
    var hadEvents = false;
    for (final evt
        in this._runHandle
            .takeEventStreamAsync(
              blockOnPendingRequest: false,
              cancellationToken,
            )
            ) {
      hadEvents = true;
      this._eventSink.add(evt);
    }
    return hadEvents;
  }

  /// A unique identifier for the session. Can be provided at the start of the
  /// session, or auto-generated.
  String get sessionId {
    return this._runHandle.sessionId;
  }

  /// Gets the current execution status of the workflow run.
  Future<RunStatus> getStatus({CancellationToken? cancellationToken}) {
    return this._runHandle.getStatusAsync(cancellationToken);
  }

  /// Gets all events emitted by the workflow.
  Iterable<WorkflowEvent> get outgoingEvents {
    return this._eventSink;
  }

  /// The number of events emitted by the workflow since the last access to
  /// [NewEvents]
  int get newEventCount {
    return this._eventSink.length - this._lastBookmark;
  }

  /// Resume execution of the workflow with the provided external responses.
  ///
  /// Returns: `true` if the workflow had any output events, `false` otherwise.
  ///
  /// [responses] An array of [ExternalResponse] objects to send to the
  /// workflow.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future<bool> resume(
    CancellationToken cancellationToken, {
    Iterable<ExternalResponse>? responses,
    Iterable<T>? messages,
  }) async {
    for (final response in responses) {
      await this._runHandle
          .enqueueResponseAsync(response, cancellationToken)
          ;
    }
    return await this
        .runToNextHaltAsync(cancellationToken)
        ;
  }

  @override
  Future dispose() {
    return this._runHandle.disposeAsync();
  }
}
