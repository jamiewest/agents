/// Specifies the current operational state of a workflow run.
enum RunStatus {
  /// The run has not yet started.
  notStarted,

  /// The run has halted with no outstanding external requests.
  idle,

  /// The run has halted with at least one outstanding external request.
  pendingRequests,

  /// The run has ended.
  ended,

  /// The workflow is currently running.
  running,
}
