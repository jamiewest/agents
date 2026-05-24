/// Provides streaming aggregation functions for processing input sequences
/// in a stateful, incremental manner.
///
/// Each factory method returns a two-argument accumulator function
/// `(TResult? running, TInput input) → TResult?` suitable for use with
/// [Iterable.fold] or similar streaming patterns.
abstract final class StreamingAggregators {
  /// Returns an accumulator that captures the first input after converting it
  /// with [conversion].
  ///
  /// Subsequent inputs are ignored.
  static TResult? Function(TResult?, TInput) first<TInput, TResult>(
    TResult Function(TInput) conversion,
  ) =>
      (TResult? running, TInput input) => running ?? conversion(input);

  /// Returns an accumulator that captures the first input element unchanged.
  ///
  /// Subsequent inputs are ignored.
  static TInput? Function(TInput?, TInput) firstOf<TInput>() =>
      (TInput? running, TInput input) => running ?? input;

  /// Returns an accumulator that keeps the most recent input after converting
  /// it with [conversion].
  static TResult? Function(TResult?, TInput) last<TInput, TResult>(
    TResult Function(TInput) conversion,
  ) =>
      (TResult? _, TInput input) => conversion(input);

  /// Returns an accumulator that keeps the most recent input element unchanged.
  static TInput? Function(TInput?, TInput) lastOf<TInput>() =>
      (TInput? _, TInput input) => input;

  /// Returns an accumulator that builds a sequence of results by applying
  /// [conversion] to each input.
  static Iterable<TResult>? Function(Iterable<TResult>?, TInput)
  union<TInput, TResult>(TResult Function(TInput) conversion) =>
      (Iterable<TResult>? running, TInput input) {
        final converted = conversion(input);
        return running != null ? [...running, converted] : [converted];
      };

  /// Returns an accumulator that builds a sequence of all input elements
  /// unchanged.
  static Iterable<TInput>? Function(Iterable<TInput>?, TInput)
  unionOf<TInput>() =>
      (Iterable<TInput>? running, TInput input) =>
          running != null ? [...running, input] : [input];
}
