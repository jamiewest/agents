/// Configuration options for workflow telemetry.
class WorkflowTelemetryOptions {
  WorkflowTelemetryOptions();

  /// Gets or sets a value indicating whether potentially sensitive information
  /// should be included in telemetry.
  ///
  /// Remarks: By default, telemetry includes metadata but not raw inputs and
  /// outputs, such as message content and executor data.
  bool enableSensitiveData;

  /// Gets or sets a value indicating whether workflow build activities should
  /// be disabled.
  bool disableWorkflowBuild;

  /// Gets or sets a value indicating whether workflow run activities should be
  /// disabled.
  bool disableWorkflowRun;

  /// Gets or sets a value indicating whether executor process activities should
  /// be disabled.
  bool disableExecutorProcess;

  /// Gets or sets a value indicating whether edge group process activities
  /// should be disabled.
  bool disableEdgeGroupProcess;

  /// Gets or sets a value indicating whether message send activities should be
  /// disabled.
  bool disableMessageSend;
}
