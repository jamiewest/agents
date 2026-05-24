import 'workflow_event.dart';

/// Event emitted when a workflow starts.
class WorkflowStartedEvent extends WorkflowEvent {
  /// Creates a workflow-started event.
  const WorkflowStartedEvent({super.data});
}
