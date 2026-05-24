import 'executor_event.dart';

/// Event emitted when an executor fails.
class ExecutorFailedEvent extends ExecutorEvent {
  /// Creates an executor-failed event.
  const ExecutorFailedEvent({required super.executorId, required this.error})
    : super(data: error);

  /// Gets the executor error.
  final Object error;
}
