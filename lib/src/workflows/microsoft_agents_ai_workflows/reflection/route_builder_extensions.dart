import '../workflow_builder.dart';
import 'reflecting_executor.dart';

/// [WorkflowBuilder] edge-routing extensions for [ReflectingExecutor].
extension RouteBuilderExtensions on WorkflowBuilder {
  /// Adds a type-filtered direct edge from [sourceExecutorId] to
  /// [targetExecutor] for each message type registered in
  /// [ReflectingExecutor.handlerTypes].
  ///
  /// This replaces the C# `AddEdgesForHandlers` helper, which used runtime
  /// reflection to discover `[MessageHandler]` parameter types. In Dart the
  /// types are explicit (registered via [HandlerRegistry.on]), so this
  /// method simply iterates [ReflectingExecutor.handlerTypes] and calls
  /// [WorkflowBuilder.addEdge] with the corresponding [messageType] filter.
  ///
  /// Example:
  /// ```dart
  /// final dispatcher = MyDispatchingExecutor('dispatcher');
  /// final handler   = MyReflectingExecutor('handler');
  ///
  /// final workflow = WorkflowBuilder(ExecutorInstanceBinding(dispatcher))
  ///     .bindReflectingExecutor(handler)
  ///     .addEdgesForHandlers('dispatcher', handler)
  ///     .addOutput('handler')
  ///     .build();
  /// ```
  WorkflowBuilder addEdgesForHandlers(
    String sourceExecutorId,
    ReflectingExecutor targetExecutor,
  ) {
    for (final type in targetExecutor.handlerTypes) {
      addEdge(sourceExecutorId, targetExecutor.id, messageType: type);
    }
    return this;
  }
}
