import '../../func_typedefs.dart';
import 'executor_binding.dart';
import 'switch_builder.dart';
import 'workflow_builder.dart';

/// Provides extension methods for configuring and building workflows using
/// the WorkflowBuilder type.
///
/// Remarks: These extension methods simplify the process of connecting
/// executors, adding external calls, and constructing workflows with output
/// aggregation. They are intended to streamline workflow graph construction
/// and promote common patterns for chaining and aggregating workflow steps.
extension WorkflowBuilderExtensions on WorkflowBuilder {
  /// Adds edges to the workflow that forward messages of the specified type
/// from the source executor to one or more target executors.
///
/// Returns: The updated [WorkflowBuilder] instance.
///
/// [builder] The [WorkflowBuilder] to which the edges will be added.
///
/// [source] The source executor from which messages will be forwarded.
///
/// [target] The target executor to which messages will be forwarded.
///
/// [TMessage] The type of message to forward.
WorkflowBuilder forwardMessage<TMessage>(
  ExecutorBinding source,
  {ExecutorBinding? target, Iterable<ExecutorBinding>? targets, Func<TMessage, bool>? condition, }
) {
return builder.forwardMessage<TMessage>(source, [target], condition: null);
 }
/// Adds edges from the specified source to the provided executors, excluding
/// messages of a specified type.
///
/// Returns: The updated [WorkflowBuilder] instance with the added edges.
///
/// [builder] The [WorkflowBuilder] instance to which the edges will be added.
///
/// [source] The source executor from which messages will be forwarded.
///
/// [target] The target executor to which messages, except those of type
/// `TMessage`, will be forwarded.
///
/// [TMessage] The type of messages to exclude from being forwarded to the
/// executors.
WorkflowBuilder forwardExcept<TMessage>(
  ExecutorBinding source,
  {ExecutorBinding? target, Iterable<ExecutorBinding>? targets, }
) {
return builder.forwardExcept<TMessage>(source, [target]);
 }
/// Adds a sequential chain of executors to the workflow, connecting each
/// executor in order so that each is executed after the previous one.
///
/// Remarks: Each executor in the chain is connected so that execution flows
/// from the source to each subsequent executor in the order provided.
///
/// Returns: The original workflow builder instance with the specified
/// executor chain added.
///
/// [builder] The workflow builder to which the executor chain will be added.
///
/// [source] The initial executor in the chain. Cannot be null.
///
/// [executors] An ordered sequence of executors to be added to the chain
/// after the source.
///
/// [allowRepetition] If set to `true`, the same executor can be added to the
/// chain multiple times.
WorkflowBuilder addChain(
  ExecutorBinding source,
  List<ExecutorBinding> executors,
  {bool? allowRepetition, }
) {
var seenExecutors = [source.id];
for (final executor in executors) {
  executor;
  if (!allowRepetition && seenExecutors.contains(executor.id)) {
    throw ArgumentError(
      "Executor ${executor.id} is already in the chain.",
      'executors',
    );
  }

  seenExecutors.add(executor.id);
  builder.addEdge(source, executor, idempotent: true);
  source = executor;
}
return builder;
 }
/// Adds an external call to the workflow by connecting the specified source
/// to a new input port with the given request and response types.
///
/// Remarks: This method creates a bidirectional connection between the source
/// and the new input port, allowing the workflow to send requests and receive
/// responses through the specified external call. The port is configured to
/// handle messages of the specified request and response types.
///
/// Returns: The original workflow builder instance with the external call
/// added.
///
/// [builder] The workflow builder to which the external call will be added.
///
/// [source] The source executor representing the external system or process
/// to connect. Cannot be null.
///
/// [portId] The unique identifier for the input port that will handle the
/// external call. Cannot be null.
///
/// [TRequest] The type of the request message that the external call will
/// accept.
///
/// [TResponse] The type of the response message that the external call will
/// produce.
WorkflowBuilder addExternalCall<TRequest,TResponse>(ExecutorBinding source, String portId, ) {
var port = new(portId, TRequest, TResponse);
return builder.addEdge(source, port)
                      .addEdge(port, source);
 }
/// Adds a switch step to the workflow, allowing conditional branching based
/// on the specified source executor.
///
/// Remarks: Use this method to introduce conditional logic into a workflow,
/// enabling execution to follow different paths based on the outcome of the
/// source executor. The switch configuration defines the available branches
/// and their associated conditions.
///
/// Returns: The workflow builder instance with the configured switch step
/// added.
///
/// [builder] The workflow builder to which the switch step will be added.
/// Cannot be null.
///
/// [source] The source executor that determines the branching condition for
/// the switch. Cannot be null.
///
/// [configureSwitch] An action used to configure the switch builder,
/// specifying the branches and their conditions. Cannot be null.
WorkflowBuilder addSwitch(ExecutorBinding source, Action<SwitchBuilder> configureSwitch, ) {
var switchBuilder = new();
configureSwitch(switchBuilder);
return switchBuilder.reduceToFanOut(builder, source);
 }
 }
