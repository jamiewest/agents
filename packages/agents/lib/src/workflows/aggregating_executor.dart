import 'package:extensions/system.dart';

import 'executor.dart';
import 'workflow_context.dart';

/// Abstract base for fan-in aggregation executors.
///
/// The fan-in router delivers a [List<Object?>] of accumulated messages.
/// [AggregatingExecutor] type-filters that list to [T] and delegates to
/// [aggregate] for processing.
abstract class AggregatingExecutor<T, TOutput>
    extends Executor<List<Object?>, TOutput> {
  /// Creates an aggregating executor with [id].
  AggregatingExecutor(super.id);

  @override
  Future<TOutput> handle(
    List<Object?> messages,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) => aggregate(
    messages.whereType<T>().toList(),
    context,
    cancellationToken: cancellationToken,
  );

  /// Processes a typed list of aggregated [messages] and returns a result.
  Future<TOutput> aggregate(
    List<T> messages,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  });
}
