import 'dart:async';

import 'external_request.dart';
import 'external_response.dart';

/// Tracks an outstanding external request and its eventual response.
class ExternalRequestContext<TRequest, TResponse> {
  /// Creates an external request context.
  ExternalRequestContext(this.request);

  final Completer<ExternalResponse<TResponse>> _completer =
      Completer<ExternalResponse<TResponse>>();

  /// Gets the external request.
  final ExternalRequest<TRequest, TResponse> request;

  /// Gets a future completed when the request is satisfied.
  Future<ExternalResponse<TResponse>> get response => _completer.future;

  /// Gets whether a response has already been supplied.
  bool get isCompleted => _completer.isCompleted;

  /// Completes the request with [response].
  void complete(ExternalResponse<TResponse> response) {
    if (_completer.isCompleted) {
      throw StateError('External request "${request.requestId}" is completed.');
    }
    if (response.requestId != request.requestId) {
      throw ArgumentError.value(
        response.requestId,
        'response',
        'Response requestId does not match the external request.',
      );
    }
    _completer.complete(response);
  }

  /// Completes the request with response payload [value].
  void completeValue(TResponse value) =>
      complete(request.createResponse(value));
}
