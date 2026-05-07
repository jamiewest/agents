/// Implemented by executors that can be reset between workflow runs.
abstract interface class ResettableExecutor {
  /// Attempts to reset the executor.
  Future<bool> reset();
}
