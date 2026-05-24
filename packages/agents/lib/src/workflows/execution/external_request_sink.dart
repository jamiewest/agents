import 'package:extensions/system.dart';

import '../external_request.dart';
import '../external_response.dart';

/// Accepts external requests from executors and delivers their responses.
abstract interface class ExternalRequestSink {
  /// Accepts [request] and returns the matching external response.
  Future<ExternalResponse<TResponse>> accept<TRequest, TResponse>(
    ExternalRequest<TRequest, TResponse> request, {
    CancellationToken? cancellationToken,
  });
}
