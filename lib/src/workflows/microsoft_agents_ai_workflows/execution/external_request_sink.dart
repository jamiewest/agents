import '../external_request.dart';

abstract class ExternalRequestSink {
  Future post(ExternalRequest request);
}
