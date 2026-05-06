import '../execution/execution_mode.dart';

class InProcessExecutionOptions {
  InProcessExecutionOptions();

  ExecutionMode executionMode = ExecutionMode.offThread;

  bool allowSharedWorkflow = false;
}
