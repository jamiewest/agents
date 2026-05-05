import 'executor_event.dart';

/// Event triggered when an executor handler fails.
///
/// [executorId] The unique identifier of the executor that has failed.
///
/// [err] The exception representing the error.
class ExecutorFailedEvent extends ExecutorEvent {
  /// Event triggered when an executor handler fails.
  ///
  /// [executorId] The unique identifier of the executor that has failed.
  ///
  /// [err] The exception representing the error.
  const ExecutorFailedEvent(String executorId, Exception? err);

  /// The exception that caused the executor to fail. This may be `null` if no
  /// exception was thrown.
  Exception? get data {
    return err;
  }
}
