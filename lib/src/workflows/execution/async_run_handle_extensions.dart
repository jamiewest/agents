import 'package:extensions/system.dart';

import '../workflow_output_event.dart';
import 'async_run_handle.dart';

/// Convenience extensions on [AsyncRunHandle].
extension AsyncRunHandleExtensions<TOutput> on AsyncRunHandle<TOutput> {
  /// Collects all [TOutput] values emitted by the workflow into a list.
  ///
  /// Awaits until the workflow's event stream completes (i.e. the run ends).
  Future<List<TOutput>> collectOutputAsync({
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final result = <TOutput>[];
    await for (final value in output) {
      result.add(value);
    }
    return result;
  }

  /// Returns the first [TOutput] emitted by the workflow, or `null` if none.
  Future<TOutput?> getFirstOutputOrDefaultAsync({
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    await for (final value in output) {
      return value;
    }
    return null;
  }

  /// Returns all [WorkflowOutputEvent.data] values as an untyped list.
  Future<List<Object?>> collectRawOutputAsync({
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final result = <Object?>[];
    await for (final event in events) {
      if (event is WorkflowOutputEvent) result.add(event.data);
    }
    return result;
  }
}
