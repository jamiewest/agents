/// Captures the result of invoking an executor.
class CallResult {
  /// Creates a call result.
  const CallResult({required this.executorId, this.output, this.error});

  /// Gets the invoked executor identifier.
  final String executorId;

  /// Gets the output returned by the executor.
  final Object? output;

  /// Gets the invocation error, if any.
  final Object? error;

  /// Gets whether the invocation completed successfully.
  bool get succeeded => error == null;
}
