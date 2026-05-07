import 'executor.dart';
import 'executor_binding.dart';
import 'executor_instance_binding.dart';
import 'workflow_builder.dart';

/// Fluent route builder rooted at a workflow executor.
class RouteBuilder {
  /// Creates a route builder.
  const RouteBuilder(this.workflowBuilder, this.sourceExecutorId);

  /// Gets the workflow builder being configured.
  final WorkflowBuilder workflowBuilder;

  /// Gets the current route source executor identifier.
  final String sourceExecutorId;

  /// Routes from the current source to [targetExecutorId].
  RouteBuilder to(String targetExecutorId, {Type? messageType}) {
    workflowBuilder.addEdge(
      sourceExecutorId,
      targetExecutorId,
      messageType: messageType,
    );
    return RouteBuilder(workflowBuilder, targetExecutorId);
  }

  /// Adds [binding] and routes from the current source to it.
  RouteBuilder toBinding(ExecutorBinding binding, {Type? messageType}) {
    workflowBuilder.addExecutor(binding);
    return to(binding.id, messageType: messageType);
  }

  /// Adds [executor] as a shared instance and routes to it.
  RouteBuilder toExecutor(
    Executor<dynamic, dynamic> executor, {
    Type? messageType,
  }) => toBinding(ExecutorInstanceBinding(executor), messageType: messageType);

  /// Marks the current source as workflow output.
  WorkflowBuilder toOutput() => workflowBuilder.addOutput(sourceExecutorId);

  /// Adds a fan-out edge from the current source to [targetExecutorIds].
  WorkflowBuilder fanOutTo(Iterable<String> targetExecutorIds) =>
      workflowBuilder.addFanOutEdge(sourceExecutorId, targetExecutorIds);
}
