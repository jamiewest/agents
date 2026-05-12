import 'workflow_event.dart';

/// Event emitted when a workflow requests that the run halt.
class RequestHaltEvent extends WorkflowEvent {
  /// Creates a request-halt event.
  const RequestHaltEvent({this.reason}) : super(data: reason);

  /// Gets the optional halt reason.
  final String? reason;
}
