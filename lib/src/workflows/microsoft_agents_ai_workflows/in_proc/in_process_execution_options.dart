import '../execution/execution_mode.dart';

class InProcessExecutionOptions {
  InProcessExecutionOptions();

  ExecutionMode executionMode = InProcessExecution.Default.ExecutionMode;

  bool allowSharedWorkflow;
}
