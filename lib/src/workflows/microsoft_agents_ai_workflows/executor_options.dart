/// Configuration options for Executor behavior.
class ExecutorOptions {
  ExecutorOptions();

  /// The default runner configuration.
  static final ExecutorOptions defaultValue = ExecutorOptions();

  /// If `true`, the result of a message handler that returns a value will be
  /// sent as a message from the executor.
  bool autoSendMessageHandlerResultObject = true;

  /// If `true`, the result of a message handler that returns a value will be
  /// yielded as an output of the executor.
  bool autoYieldOutputHandlerResultObject = true;
}
