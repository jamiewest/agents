import 'executor.dart';
import 'executor_binding.dart';
import 'specialized/workflow_host_executor.dart';
import 'workflow.dart';

/// Binds a sub-[Workflow] as a [WorkflowHostExecutor] inside a parent
/// workflow.
///
/// Each call to [createInstance] returns a fresh [WorkflowHostExecutor].
/// Use with [WorkflowBuilder.addExecutor] to embed one workflow inside
/// another.
class SubworkflowBinding extends ExecutorBinding {
  /// Creates a sub-workflow binding.
  SubworkflowBinding(super.id, this.subWorkflow);

  /// Gets the sub-workflow.
  final Workflow subWorkflow;

  @override
  bool get supportsResetting => true;

  @override
  Future<Executor<dynamic, dynamic>> createInstance() async =>
      WorkflowHostExecutor(subWorkflow: subWorkflow, id: id);
}
