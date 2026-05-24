import 'workflow_event.dart';

/// Base type for events associated with a workflow executor.
class ExecutorEvent extends WorkflowEvent {
  /// Creates an executor event.
  const ExecutorEvent({required this.executorId, super.data});

  /// Gets the executor identifier.
  final String executorId;
}
