/// Configuration options for workflow telemetry.
class WorkflowTelemetryOptions {
  /// Creates default telemetry options with no sensitive data and all
  /// activities enabled.
  WorkflowTelemetryOptions();

  /// Whether to include potentially sensitive data (raw inputs/outputs) in
  /// telemetry. Defaults to `false`.
  bool enableSensitiveData = false;

  /// Whether to disable `workflow.build` activities. Defaults to `false`.
  bool disableWorkflowBuild = false;

  /// Whether to disable `workflow_invoke` activities. Defaults to `false`.
  bool disableWorkflowRun = false;

  /// Whether to disable `executor.process` activities. Defaults to `false`.
  bool disableExecutorProcess = false;

  /// Whether to disable `edge_group.process` activities. Defaults to `false`.
  bool disableEdgeGroupProcess = false;

  /// Whether to disable `message.send` activities. Defaults to `false`.
  bool disableMessageSend = false;

  /// Whether to disable `workflow.session` activities. Defaults to `false`.
  bool disableWorkflowSession = false;
}
