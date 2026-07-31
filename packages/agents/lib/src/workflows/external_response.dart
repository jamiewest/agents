import 'request_port.dart';

/// Represents a response to an [ExternalRequest].
class ExternalResponse<TResponse> {
  /// Creates an external response.
  const ExternalResponse({
    required this.requestId,
    required this.port,
    required TResponse response,
  }) : _response = response,
       isPending = false;

  /// Creates a placeholder for a request whose response has not arrived yet.
  ///
  /// `sendRequest` returns one of these: the real response is delivered to
  /// the requesting executor as a message in a later superstep, once it is
  /// supplied via `addExternalResponse` / `sendResponseAsync`. Reading
  /// [response] on a pending placeholder throws unless [TResponse] is
  /// nullable (in which case it reads as `null`).
  const ExternalResponse.pending({required this.requestId, required this.port})
    : _response = null,
      isPending = true;

  /// Gets the request identifier this response satisfies.
  final String requestId;

  /// Gets the external request port descriptor.
  final RequestPortDescriptor port;

  /// Whether this is a placeholder created before the response arrived.
  final bool isPending;

  final Object? _response;

  /// Gets the response payload.
  ///
  /// Throws a [StateError] when this is a pending placeholder for a
  /// non-nullable [TResponse].
  TResponse get response {
    final value = _response;
    if (!isPending) return value as TResponse;
    if (value is TResponse) return value;
    throw StateError(
      'The response for request "$requestId" on port "${port.id}" has not '
      'arrived yet. sendRequest returns a pending placeholder; the actual '
      'response is delivered to the requesting executor as a message in a '
      'later superstep.',
    );
  }
}
