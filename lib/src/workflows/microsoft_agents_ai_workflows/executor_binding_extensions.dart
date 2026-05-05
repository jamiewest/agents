import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'executor.dart';
import 'request_port.dart';
import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../func_typedefs.dart';
import 'configured_executor_binding.dart';
import 'executor_binding.dart';
import 'executor_instance_binding.dart';
import 'executor_options.dart';
import 'protocol_descriptor.dart';
import 'subworkflow_binding.dart';
import 'workflow.dart';
import 'workflow_context.dart';

/// Extension methods for configuring executors and functions as
/// [ExecutorBinding] instances.
extension ExecutorBindingExtensions on Executor {
  /// Configures an [Executor] instance for use in a workflow.
///
/// Remarks: Note that Executor Ids must be unique within a workflow.
///
/// Returns: An [ExecutorBinding] instance wrapping the specified [Executor].
///
/// [executor] The executor instance.
ExecutorBinding bindExecutor({Func2<String, String, Future<TExecutor>>? factoryAsync, String? id, TOptions? options, }) {
return executorInstanceBinding(executor);
 }
/// Configures a factory method for creating an [Executor] of type
/// `TExecutor`, using the type name as the id.
///
/// Remarks: Note that Executor Ids must be unique within a workflow. Although
/// this will generally result in a delay-instantiated [Executor] once
/// messages are available for it, it will be instantiated if a
/// [ProtocolDescriptor] for the [Workflow] is requested, and it is the
/// starting executor.
///
/// Returns: An [ExecutorBinding] instance that resolves to the result of the
/// factory call when messages get sent to it.
///
/// [factoryAsync] The factory method.
///
/// [TExecutor] The type of the resulting executor
ExecutorBinding configureFactory<TExecutor>({String? id, TOptions? options, }) {
return factoryAsync.bindExecutor();
 }
ConfiguredExecutorBinding toBinding<TInput>({FunctionExecutor<TInput>? executor}) {
return new(Configured.fromInstance(executor, raw: raw)
                         .superValue<FunctionExecutor<TInput>, Executor>(),
            FunctionExecutor<TInput>);
 }
/// Configures a sub-workflow executor for the specified workflow, using the
/// provided identifier and options.
///
/// Returns: An ExecutorRegistration instance representing the configured
/// sub-workflow executor.
///
/// [workflow] The workflow instance to be executed as a sub-workflow. Cannot
/// be null.
///
/// [id] A unique identifier for the sub-workflow execution. Used to
/// distinguish this sub-workflow instance.
///
/// [options] Optional configuration options for the sub-workflow executor. If
/// null, default options are used.
ExecutorBinding configureSubWorkflow(String id, {ExecutorOptions? options, }) {
return workflow.bindAsExecutor(id, options);
 }
/// Configures a sub-workflow executor for the specified workflow, using the
/// provided identifier and options.
///
/// Returns: An [ExecutorBinding] instance representing the configured
/// sub-workflow executor.
///
/// [workflow] The workflow instance to be executed as a sub-workflow. Cannot
/// be null.
///
/// [id] A unique identifier for the sub-workflow execution. Used to
/// distinguish this sub-workflow instance.
///
/// [options] Optional configuration options for the sub-workflow executor. If
/// null, default options are used.
ExecutorBinding bindAsExecutor({String? id, ExecutorOptions? options, Func3<TInput, WorkflowContext, CancellationToken, Future>? messageHandlerAsync, bool? threadsafe, Action3<TInput, WorkflowContext, CancellationToken>? messageHandler, Func2<TAccumulate?, TInput, TAccumulate?>? aggregatorFunc, AIAgent? agent, bool? emitEvents, RequestPort? port, bool? allowWrappedRequests, }) {
return subworkflowBinding(workflow, id, options);
 }
 }
