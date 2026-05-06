import 'executor_event.dart';

/// Event triggered when an executor handler is invoked.
///
/// [executorId] The unique identifier of the executor being invoked.
///
/// [message] The invocation message.
class ExecutorInvokedEvent extends ExecutorEvent {
  /// Event triggered when an executor handler is invoked.
  ///
  /// [executorId] The unique identifier of the executor being invoked.
  ///
  /// [message] The invocation message.
  ExecutorInvokedEvent(String executorId, Object message)
      : super(executorId, message);
}
