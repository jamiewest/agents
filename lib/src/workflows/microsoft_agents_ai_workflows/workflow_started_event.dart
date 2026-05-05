import 'workflow_event.dart';

/// Event triggered when a workflow starts execution.
///
/// [message] The message triggering the start of workflow execution.
class WorkflowStartedEvent extends WorkflowEvent {
  /// Event triggered when a workflow starts execution.
  ///
  /// [message] The message triggering the start of workflow execution.
  WorkflowStartedEvent({Object? message = null});
}
