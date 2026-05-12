import 'workflow_event.dart';

/// Event emitted when a workflow yields output.
class WorkflowOutputEvent extends WorkflowEvent {
  /// Creates a workflow-output event.
  const WorkflowOutputEvent({required this.executorId, super.data});

  /// Gets the source executor identifier.
  final String executorId;
}
