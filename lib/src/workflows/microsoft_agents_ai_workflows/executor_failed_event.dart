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
  ExecutorFailedEvent(String executorId, this.err)
      : super(executorId, err);

  /// The exception that caused the executor to fail. This may be `null` if no
  /// exception was thrown.
  final Exception? err;
}
