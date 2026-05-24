import 'workflow_event.dart';

/// Event emitted for a non-fatal workflow warning.
class WorkflowWarningEvent extends WorkflowEvent {
  /// Creates a workflow warning event.
  const WorkflowWarningEvent(this.message) : super(data: message);

  /// Gets the warning message.
  final String message;
}
