import '../executor_instance_binding.dart';
import '../workflow_builder.dart';
import 'reflecting_executor.dart';

/// [WorkflowBuilder] extensions for [ReflectingExecutor].
extension ReflectionExtensions on WorkflowBuilder {
  /// Adds a [ReflectingExecutor] instance to the workflow.
  ///
  /// Equivalent to [WorkflowBuilder.addExecutor] with an
  /// [ExecutorInstanceBinding], but scoped to [ReflectingExecutor] so the
  /// return type is preserved for fluent chaining with
  /// [RouteBuilderExtensions.addEdgesForHandlers].
  WorkflowBuilder bindReflectingExecutor(ReflectingExecutor executor) =>
      addExecutor(ExecutorInstanceBinding(executor));
}
