import 'request_port.dart';

/// Represents a response to an [ExternalRequest].
class ExternalResponse<TResponse> {
  /// Creates an external response.
  const ExternalResponse({
    required this.requestId,
    required this.port,
    required this.response,
  });

  /// Gets the request identifier this response satisfies.
  final String requestId;

  /// Gets the external request port descriptor.
  final RequestPortDescriptor port;

  /// Gets the response payload.
  final TResponse response;
}
