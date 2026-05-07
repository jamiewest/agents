import 'workflow_event.dart';

/// Event emitted for a workflow error.
class WorkflowErrorEvent extends WorkflowEvent {
  /// Creates a workflow error event.
  const WorkflowErrorEvent(this.error) : super(data: error);

  /// Gets the workflow error.
  final Object error;
}
