import '../external_response.dart';
import '../request_port.dart';

/// Extension helpers for matching [ExternalResponse] to a [RequestPort].
extension RequestPortExtensions<TRequest, TResponse>
    on RequestPort<TRequest, TResponse> {
  /// Returns `true` when [response] was produced by this port.
  bool isResponsePort(ExternalResponse<TResponse> response) =>
      response.port.id == id;

  /// Returns `true` when [response] should be processed by this port.
  bool shouldProcessResponse(ExternalResponse<TResponse> response) =>
      isResponsePort(response);

  /// Creates an error describing a type mismatch for [response].
  StateError createExceptionForType(ExternalResponse<TResponse> response) =>
      StateError(
        'Message type ${response.response.runtimeType} is not assignable to '
        '$TResponse from port $id.',
      );
}
