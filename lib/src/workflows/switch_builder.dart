import 'executor.dart';
import 'executor_binding.dart';
import 'executor_instance_binding.dart';
import 'workflow_builder.dart';

/// Fluent builder for routing one source executor to multiple targets.
class SwitchBuilder {
  /// Creates a switch builder.
  const SwitchBuilder(this.workflowBuilder, this.sourceExecutorId);

  /// Gets the workflow builder being configured.
  final WorkflowBuilder workflowBuilder;

  /// Gets the source executor identifier.
  final String sourceExecutorId;

  /// Adds a route case to an existing target executor.
  SwitchBuilder caseTo(String targetExecutorId, {Type? messageType}) {
    workflowBuilder.addEdge(
      sourceExecutorId,
      targetExecutorId,
      messageType: messageType,
    );
    return this;
  }

  /// Adds a route case to [binding].
  SwitchBuilder caseToBinding(ExecutorBinding binding, {Type? messageType}) {
    workflowBuilder.addExecutor(binding);
    return caseTo(binding.id, messageType: messageType);
  }

  /// Adds a route case to [executor] as a shared instance.
  SwitchBuilder caseToExecutor(
    Executor<dynamic, dynamic> executor, {
    Type? messageType,
  }) => caseToBinding(
    ExecutorInstanceBinding(executor),
    messageType: messageType,
  );

  /// Adds a fan-out edge to all [targetExecutorIds].
  WorkflowBuilder fanOutTo(Iterable<String> targetExecutorIds) =>
      workflowBuilder.addFanOutEdge(sourceExecutorId, targetExecutorIds);
}
