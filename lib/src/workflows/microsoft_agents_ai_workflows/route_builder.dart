import 'dart:async';

import 'package:extensions/system.dart';

import 'executor.dart';
import 'executor_binding.dart';
import 'executor_instance_binding.dart';
import 'function_executor.dart';
import 'port_handler_executor.dart';
import 'request_port.dart';
import 'workflow_builder.dart';
import 'workflow_context.dart';

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

  // ── inline handler registration ───────────────────────────────────────────

  /// Creates an [ActionExecutor] from [handler] and routes the current source
  /// to it.
  ///
  /// [id] defaults to `'handler_TInput'` if omitted.
  RouteBuilder addHandler<TInput>(
    FutureOr<void> Function(
      TInput input,
      WorkflowContext context,
      CancellationToken cancellationToken,
    )
    handler, {
    String? id,
  }) {
    final executor = ActionExecutor<TInput>(
      id ?? 'handler_${TInput.toString()}',
      handler,
    );
    return toBinding(ExecutorInstanceBinding(executor), messageType: TInput);
  }

  /// Creates a [FunctionExecutor] from [handler] that produces results of type
  /// [TResult] and routes the current source to it.
  ///
  /// [id] defaults to `'handler_TInput_TResult'` if omitted.
  RouteBuilder addResultHandler<TInput, TResult>(
    FutureOr<TResult> Function(
      TInput input,
      WorkflowContext context,
      CancellationToken cancellationToken,
    )
    handler, {
    String? id,
  }) {
    final executor = FunctionExecutor<TInput, TResult>(
      id ?? 'handler_${TInput.toString()}_${TResult.toString()}',
      handler,
    );
    return toBinding(ExecutorInstanceBinding(executor), messageType: TInput);
  }

  /// Creates a catch-all [FunctionExecutor] that receives any message type not
  /// handled by typed executors upstream.
  ///
  /// [id] defaults to `'catch_all'` if omitted.
  RouteBuilder addCatchAll(
    FutureOr<void> Function(
      Object message,
      WorkflowContext context,
      CancellationToken cancellationToken,
    )
    handler, {
    String? id,
  }) {
    final executor = ActionExecutor<Object>(
      id ?? 'catch_all',
      handler,
      configureProtocolCallback: (b) => b.acceptsAllMessages(),
    );
    return toBinding(ExecutorInstanceBinding(executor));
  }

  /// Creates a [PortHandlerExecutor] that handles external requests arriving
  /// on [port] and routes the current source to it.
  ///
  /// [id] defaults to `'port_handler_port.id'` if omitted.
  RouteBuilder addPortHandler<TRequest, TResponse>(
    RequestPort<TRequest, TResponse> port,
    FutureOr<TResponse> Function(
      TRequest request,
      WorkflowContext context,
      CancellationToken cancellationToken,
    )
    handler, {
    String? id,
  }) {
    final executor = PortHandlerExecutor<TRequest, TResponse>(
      id ?? 'port_handler_${port.id}',
      port,
      handler,
    );
    return toBinding(ExecutorInstanceBinding(executor), messageType: TRequest);
  }
}
