import '../../func_typedefs.dart';

/// Provides a set of streaming aggregation functions for processing sequences
/// of input values in a stateful, incremental manner.
class StreamingAggregators {
  StreamingAggregators();

  /// Creates a streaming aggregator that returns the result of applying the
  /// specified conversion function to the first input value.
  static Func2<TResult?, TInput, TResult?> first<TInput, TResult>({
    Func<TInput, TResult>? conversion,
  }) {
    return (TResult? runningResult, TInput input) {
      runningResult ??= conversion?.call(input);
      return runningResult;
    };
  }

  /// Creates a streaming aggregator that returns the result of applying the
  /// specified conversion to the most recent input value.
  static Func2<TResult?, TInput, TResult?> last<TInput, TResult>({
    Func<TInput, TResult>? conversion,
  }) {
    return (TResult? runningResult, TInput input) {
      return conversion?.call(input);
    };
  }

  /// Creates a streaming aggregator that produces the union of results by
  /// applying a conversion function to each input and accumulating the results.
  static Func2<Iterable<TResult>?, TInput, Iterable<TResult>?>
  union<TInput, TResult>({Func<TInput, TResult>? conversion}) {
    return (Iterable<TResult>? runningResult, TInput input) {
      final item = conversion?.call(input);
      if (item == null) return runningResult;
      return runningResult != null ? [...runningResult, item] : [item];
    };
  }
}
