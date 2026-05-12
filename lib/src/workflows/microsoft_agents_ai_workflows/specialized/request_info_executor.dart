import 'package:extensions/system.dart';

import '../execution/external_request_sink.dart';
import '../executor.dart';
import '../external_request.dart';
import '../external_response.dart';
import '../protocol_builder.dart';
import '../request_port.dart';
import '../workflow_context.dart';

/// Executor that routes typed requests to an [ExternalRequestSink] and
/// returns the external response.
///
/// Accepts both raw [TRequest] messages and pre-wrapped
/// [ExternalRequest]`<TRequest, TResponse>` inputs.
class RequestInfoExecutor<TRequest extends Object,
    TResponse extends Object> extends Executor<Object, Object?> {
  /// Creates a [RequestInfoExecutor].
  RequestInfoExecutor(super.id, this.port, this.sink);

  /// Gets the request port used by this executor.
  final RequestPort<TRequest, TResponse> port;

  /// Gets the sink that accepts and fulfils external requests.
  final ExternalRequestSink sink;

  int _counter = 0;

  @override
  void configureProtocol(ProtocolBuilder builder) {
    builder.acceptsMessage<TRequest>();
    builder.acceptsMessage<ExternalRequest<TRequest, TResponse>>();
    builder.sendsMessage<ExternalResponse<TResponse>>();
  }

  @override
  Future<Object?> handle(
    Object message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();

    final ExternalRequest<TRequest, TResponse> request;
    if (message is ExternalRequest<TRequest, TResponse>) {
      request = message;
    } else if (message is TRequest) {
      request = ExternalRequest<TRequest, TResponse>(
        requestId: '$id-${++_counter}',
        port: port,
        request: message,
      );
    } else {
      throw StateError(
        'Unexpected message type for executor $id: ${message.runtimeType}',
      );
    }

    return sink.accept<TRequest, TResponse>(
      request,
      cancellationToken: token,
    );
  }
}
