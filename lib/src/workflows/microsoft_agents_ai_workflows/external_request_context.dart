import 'execution/external_request_sink.dart';
import 'request_port.dart';

abstract class ExternalRequestContext {
  ExternalRequestSink registerPort(RequestPort port);
}
