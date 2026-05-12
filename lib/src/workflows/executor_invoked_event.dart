import 'executor_event.dart';

/// Event emitted when an executor is invoked.
class ExecutorInvokedEvent extends ExecutorEvent {
  /// Creates an executor-invoked event.
  const ExecutorInvokedEvent({required super.executorId, super.data});
}
