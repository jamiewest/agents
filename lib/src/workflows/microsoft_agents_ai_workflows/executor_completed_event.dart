import 'executor_event.dart';

/// Event emitted when an executor completes.
class ExecutorCompletedEvent extends ExecutorEvent {
  /// Creates an executor-completed event.
  const ExecutorCompletedEvent({required super.executorId, super.data});
}
