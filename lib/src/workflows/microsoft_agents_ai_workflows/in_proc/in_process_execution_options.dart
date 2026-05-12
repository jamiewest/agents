import '../execution/execution_mode.dart';

/// Configuration options for in-process workflow execution.
class InProcessExecutionOptions {
  /// Creates [InProcessExecutionOptions].
  const InProcessExecutionOptions({
    this.executionMode = ExecutionMode.offThread,
    this.allowSharedWorkflow = false,
  });

  /// The execution mode used when running the workflow.
  final ExecutionMode executionMode;

  /// Whether to allow the same [Workflow] instance to be shared across
  /// concurrent runs without taking exclusive ownership.
  final bool allowSharedWorkflow;
}
