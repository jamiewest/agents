/// Provides a mechanism to return an executor to a 'reset' state, allowing a
/// workflow containing shared instances of it to be resued after a run is
/// disposed.
abstract class ResettableExecutor {
  /// Reset the executor
  ///
  /// Returns: A [ValueTask] representing the completion of the reset operation.
  Future reset();
}
