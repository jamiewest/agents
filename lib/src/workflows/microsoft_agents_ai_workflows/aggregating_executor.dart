import 'package:extensions/system.dart';
import '../../func_typedefs.dart';
import 'executor_options.dart';
import 'portable_value.dart';
import 'streaming_aggregators.dart';
import 'workflow_context.dart';

/// Executes a workflow step that incrementally aggregates input messages
/// using a user-provided aggregation function.
///
/// Remarks: The aggregate state is persisted and restored automatically
/// during workflow checkpointing. This executor is suitable for scenarios
/// where stateful, incremental aggregation of messages is required, such as
/// running totals or event accumulation.
///
/// [id] The unique identifier for this executor instance.
///
/// [aggregator] A function that computes the new aggregate state from the
/// previous aggregate and the current input message. The function receives
/// the current aggregate (or null if this is the first message) and the input
/// message, and returns the updated aggregate.
///
/// [options] Optional configuration settings for the executor. If null,
/// default options are used.
///
/// [declareCrossRunShareable] Declare that this executor may be used
/// simultaneously by multiple runs safely.
///
/// [TInput] The type of input messages to be processed and aggregated.
///
/// [TAggregate] The type representing the aggregate state produced by the
/// aggregator function.
class AggregatingExecutor<TInput,TAggregate> extends Executor<TInput, TAggregate?> {
  /// Executes a workflow step that incrementally aggregates input messages
  /// using a user-provided aggregation function.
  ///
  /// Remarks: The aggregate state is persisted and restored automatically
  /// during workflow checkpointing. This executor is suitable for scenarios
  /// where stateful, incremental aggregation of messages is required, such as
  /// running totals or event accumulation.
  ///
  /// [id] The unique identifier for this executor instance.
  ///
  /// [aggregator] A function that computes the new aggregate state from the
  /// previous aggregate and the current input message. The function receives
  /// the current aggregate (or null if this is the first message) and the input
  /// message, and returns the updated aggregate.
  ///
  /// [options] Optional configuration settings for the executor. If null,
  /// default options are used.
  ///
  /// [declareCrossRunShareable] Declare that this executor may be used
  /// simultaneously by multiple runs safely.
  ///
  /// [TInput] The type of input messages to be processed and aggregated.
  ///
  /// [TAggregate] The type representing the aggregate state produced by the
  /// aggregator function.
  AggregatingExecutor(
    String id,
    Func2<TAggregate?, TInput, TAggregate?> aggregator,
    {ExecutorOptions? options = null, bool? declareCrossRunShareable = null, },
  );

  @override
  Future<TAggregate?> handle(
    TInput message,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async  {
    var runningAggregate = null;
    await context.invokeWithStateAsync<PortableValue>(
      InvokeAggregatorAsync,
      AggregateStateKey,
      cancellationToken: cancellationToken,
    )
                     ;
    return runningAggregate;
    /* TODO: unsupported node kind "unknown" */
    // ValueTask<PortableValue?> InvokeAggregatorAsync(PortableValue? maybeState, IWorkflowContext context, CancellationToken cancellationToken)
    //         {
      //             if (maybeState == null || !maybeState.Is(runningAggregate))
      //             {
        //                 runningAggregate = null;
        //             }
      //
      //             runningAggregate = aggregator(runningAggregate, message);
      //
      //             if (runningAggregate == null)
      //             {
        //                 return new((PortableValue?)null);
        //             }
      //
      //             return new(new PortableValue(runningAggregate));
      //         }
  }
}
