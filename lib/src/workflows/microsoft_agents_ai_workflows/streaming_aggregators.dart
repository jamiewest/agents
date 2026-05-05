import '../../func_typedefs.dart';

/// Provides a set of streaming aggregation functions for processing sequences
/// of input values in a stateful, incremental manner.
class StreamingAggregators {
  StreamingAggregators();

  /// Creates a streaming aggregator that returns the result of applying the
  /// specified conversion function to the first input value.
  ///
  /// Remarks: Subsequent inputs after the first are ignored by the aggregator.
  /// This method is useful for scenarios where only the first occurrence in a
  /// stream is relevant. The conversion function is invoked at most once.
  ///
  /// Returns: An aggregation function that yields the result of converting the
  /// first input using the specified function.
  ///
  /// [conversion] A function that converts an input value of type `TInput` to a
  /// result of type `TResult`. This function is applied to the first input
  /// received.
  ///
  /// [TInput] The type of the input elements to be aggregated.
  ///
  /// [TResult] The type of the result produced by the conversion function.
  static Func2<TResult?, TInput, TResult?> first<TInput, TResult>({
    Func<TInput, TResult>? conversion,
  }) {
    return Aggregate;
    /* TODO: unsupported node kind "unknown" */
    // TResult? Aggregate(TResult? runningResult, TInput input)
    //         {
    //             runningResult ??= conversion(input);
    //             return runningResult;
    //         }
  }

  /// Creates a streaming aggregator that returns the result of applying the
  /// specified conversion to the most recent input value.
  ///
  /// Returns: A aggregator function that yields the result of converting the
  /// last input received using the specified function.
  ///
  /// [conversion] A function that converts each input value to a result. Cannot
  /// be null.
  ///
  /// [TInput] The type of the input elements to be aggregated.
  ///
  /// [TResult] The type of the result produced by the conversion function.
  static Func2<TResult?, TInput, TResult?> last<TInput, TResult>({
    Func<TInput, TResult>? conversion,
  }) {
    return Aggregate;
    /* TODO: unsupported node kind "unknown" */
    // TResult? Aggregate(TResult? runningResult, TInput input)
    //         {
    //             return conversion(input);
    //         }
  }

  /// Creates a streaming aggregator that produces the union of results by
  /// applying a conversion function to each input and accumulating the results.
  ///
  /// Returns: An aggregator function that, for each input, returns an
  /// enumerable containing the result of converting every element produced so
  /// far.
  ///
  /// [conversion] A function that converts each input element to a result
  /// element to be included in the union.
  ///
  /// [TInput] The type of the input elements to be aggregated.
  ///
  /// [TResult] The type of the result elements produced by the conversion
  /// function.
  static Func2<Iterable<TResult>?, TInput, Iterable<TResult>?>
  union<TInput, TResult>({Func<TInput, TResult>? conversion}) {
    return Aggregate;
    /* TODO: unsupported node kind "unknown" */
    // Iterable<TResult> Aggregate(Iterable<TResult>? runningResult, TInput input)
    //         {
    //             return runningResult is not null ? runningResult.Append(conversion(input)) : [conversion(input)];
    //         }
  }
}
