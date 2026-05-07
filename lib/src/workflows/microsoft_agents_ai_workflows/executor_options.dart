/// Options that describe runtime behavior for an executor registration.
class ExecutorOptions {
  /// Creates executor options.
  const ExecutorOptions({
    this.supportsConcurrentSharedExecution = true,
    this.supportsResetting = false,
  });

  /// Gets whether a shared executor instance can be used concurrently.
  final bool supportsConcurrentSharedExecution;

  /// Gets whether the executor can be reset between workflow runs.
  final bool supportsResetting;
}
