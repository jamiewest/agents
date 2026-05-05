import 'external_request.dart';
import 'request_halt_event.dart';

/// Specifies the current operational state of a workflow run.
enum RunStatus {
  /// The run has not yet started. This only occurs when running in "lockstep"
  /// mode.
  notStarted,

  /// The run has halted, has no outstanding requets, but has not received a
  /// [RequestHaltEvent].
  idle,

  /// The run has halted, and has at least one outstanding [ExternalRequest].
  pendingRequests,

  /// The user has ended the run. No further events will be emitted, and no
  /// messages can be sent to it.
  ended,

  /// The workflow is currently running, and may receive events or requests.
  running,
}
