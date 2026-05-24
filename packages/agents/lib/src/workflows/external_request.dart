import 'external_response.dart';
import 'request_port.dart';

/// Represents a request that must be satisfied outside the workflow runtime.
class ExternalRequest<TRequest, TResponse> {
  /// Creates an external request.
  const ExternalRequest({
    required this.requestId,
    required this.port,
    required this.request,
  });

  /// Gets the request identifier.
  final String requestId;

  /// Gets the request port used by this request.
  final RequestPort<TRequest, TResponse> port;

  /// Gets the request payload.
  final TRequest request;

  /// Creates a response paired to this request.
  ExternalResponse<TResponse> createResponse(TResponse response) =>
      ExternalResponse<TResponse>(
        requestId: requestId,
        port: port.toDescriptor(),
        response: response,
      );
}
