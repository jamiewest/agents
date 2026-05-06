import 'executor_event.dart';

/// Event triggered when an executor handler has completed.
///
/// [executorId] The unique identifier of the executor that has completed.
///
/// [result] The result produced by the executor upon completion, or `null` if
/// no result is available.
class ExecutorCompletedEvent extends ExecutorEvent {
  /// Event triggered when an executor handler has completed.
  ///
  /// [executorId] The unique identifier of the executor that has completed.
  ///
  /// [result] The result produced by the executor upon completion, or `null` if
  /// no result is available.
  const ExecutorCompletedEvent(String executorId, Object? result)
      : super(executorId, result);
}
