/// This class represents the result of a call to a message handler.
class CallResult {
  CallResult({
    this.isVoid = false,
    this.isCancelled = false,
    this.result,
    this.exception,
  });

  /// Indicates whether the call was to a void-return executor.
  bool isVoid;

  /// The result of the call. Null for void handlers or failed calls.
  Object? result;

  /// The exception raised during the call, if any.
  Exception? exception;

  /// Indicates whether the call was cancelled.
  bool isCancelled;

  /// Indicates whether the call was successful.
  bool get isSuccess => exception == null && !isCancelled;

  /// Creates a [CallResult] for a successful non-void call.
  static CallResult returnResult({Object? result}) =>
      CallResult(result: result);

  /// Creates a [CallResult] for a successful void call.
  static CallResult returnVoid() => CallResult(isVoid: true);

  /// Creates a [CallResult] indicating the call was cancelled.
  static CallResult cancelled(bool wasVoid) =>
      CallResult(isVoid: wasVoid, isCancelled: true);

  /// Creates a [CallResult] indicating an exception was raised.
  static CallResult raisedException(bool wasVoid, Exception exception) =>
      CallResult(isVoid: wasVoid, exception: exception);
}
