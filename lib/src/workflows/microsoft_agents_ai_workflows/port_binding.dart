import 'package:extensions/system.dart';
import 'request_port.dart';
import 'execution/external_request_sink.dart';
import 'external_request.dart';

class PortBinding {
  const PortBinding(RequestPort port, ExternalRequestSink sink)
    : port = port,
      sink = sink;

  RequestPort get port {
    return port;
  }

  ExternalRequestSink get sink {
    return sink;
  }

  Future postRequest<TRequest>(
    TRequest request, {
    String? requestId,
    CancellationToken? cancellationToken,
  }) {
    var externalRequest = ExternalRequest.create(this.port, request, requestId);
    return this.sink.post(externalRequest);
  }
}
