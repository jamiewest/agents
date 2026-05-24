import 'external_request.dart';
import 'external_response.dart';
import 'port_binding.dart';
import 'request_port.dart';

/// Binds a request port to a Dart callback.
class RequestPortBinding<TRequest, TResponse> extends PortBinding {
  /// Creates a request port binding.
  RequestPortBinding(this.port, this.callback) : super(port.id);

  /// Gets the request port.
  final RequestPort<TRequest, TResponse> port;

  /// Gets the callback that handles external requests.
  final Future<TResponse> Function(ExternalRequest<TRequest, TResponse> request)
  callback;

  /// Invokes the bound request handler.
  Future<ExternalResponse<TResponse>> invoke(
    ExternalRequest<TRequest, TResponse> request,
  ) async {
    final response = await callback(request);
    return request.createResponse(response);
  }
}
