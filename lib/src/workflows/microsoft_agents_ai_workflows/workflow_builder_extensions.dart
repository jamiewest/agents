import 'dart:async';

import 'package:extensions/system.dart';

import 'executor.dart';
import 'executor_binding.dart';
import 'executor_instance_binding.dart';
import 'function_executor.dart';
import 'protocol_builder.dart';
import 'route_builder.dart';
import 'stateful_executor.dart';
import 'stateful_executor_options.dart';
import 'switch_builder.dart';
import 'workflow_builder.dart';
import 'workflow_context.dart';

/// C#-style workflow builder convenience methods.
extension WorkflowBuilderExtensions on WorkflowBuilder {
  /// Binds an executor instance as a shared executor.
  WorkflowBuilder bindExecutor(Executor<dynamic, dynamic> executor) =>
      addExecutor(ExecutorInstanceBinding(executor));

  /// Binds an executor binding.
  WorkflowBuilder bindExecutorBinding(ExecutorBinding binding) =>
      addExecutor(binding);

  /// Binds a function executor and returns the created executor.
  FunctionExecutor<TInput, TOutput> bindFunctionExecutor<TInput, TOutput>(
    String id,
    FutureOr<TOutput> Function(
      TInput input,
      WorkflowContext context,
      CancellationToken cancellationToken,
    )
    callback, {
    void Function(ProtocolBuilder builder)? configureProtocol,
  }) {
    final executor = FunctionExecutor<TInput, TOutput>(
      id,
      callback,
      configureProtocolCallback: configureProtocol,
    );
    addExecutor(ExecutorInstanceBinding(executor));
    return executor;
  }

  /// Binds an action executor and returns the created executor.
  ActionExecutor<TInput> bindActionExecutor<TInput>(
    String id,
    FutureOr<void> Function(
      TInput input,
      WorkflowContext context,
      CancellationToken cancellationToken,
    )
    callback, {
    void Function(ProtocolBuilder builder)? configureProtocol,
  }) {
    final executor = ActionExecutor<TInput>(
      id,
      callback,
      configureProtocolCallback: configureProtocol,
    );
    addExecutor(ExecutorInstanceBinding(executor));
    return executor;
  }

  /// Binds a callback-backed stateful executor.
  FunctionStatefulExecutor<TState, TInput, TOutput>
  bindStatefulFunctionExecutor<TState, TInput, TOutput>(
    String id,
    FutureOr<TOutput> Function(
      TInput input,
      WorkflowContext context,
      TState? state,
      CancellationToken cancellationToken,
    )
    callback, {
    StatefulExecutorOptions<TState>? options,
    void Function(ProtocolBuilder builder)? configureProtocol,
  }) {
    final executor = FunctionStatefulExecutor<TState, TInput, TOutput>(
      id,
      callback,
      options: options,
      configureProtocolCallback: configureProtocol,
    );
    addExecutor(ExecutorInstanceBinding(executor));
    return executor;
  }

  /// Starts a fluent route from [sourceExecutorId].
  RouteBuilder routeFrom(String sourceExecutorId) =>
      RouteBuilder(this, sourceExecutorId);

  /// Starts a fluent switch from [sourceExecutorId].
  SwitchBuilder switchFrom(String sourceExecutorId) =>
      SwitchBuilder(this, sourceExecutorId);

  /// Marks [executorId] as workflow output.
  WorkflowBuilder outputFrom(String executorId) => addOutput(executorId);
}
