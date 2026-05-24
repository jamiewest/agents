import 'dart:async';

import 'package:extensions/system.dart';

import 'executor.dart';
import 'external_request.dart';
import 'protocol_builder.dart';
import 'request_port.dart';
import 'workflow_context.dart';

/// A workflow executor that responds to external requests arriving on [port].
///
/// Receives [ExternalRequest] messages routed to it, calls [handler] with the
/// unwrapped request payload, and produces the [ExternalResponse] via
/// [WorkflowContext.yieldOutput].
class PortHandlerExecutor<TRequest, TResponse>
    extends Executor<ExternalRequest<TRequest, TResponse>, TResponse> {
  /// Creates a port handler executor.
  PortHandlerExecutor(super.id, this.port, this.handler);

  /// Gets the request port this executor handles.
  final RequestPort<TRequest, TResponse> port;

  /// Gets the handler invoked for each incoming request.
  final FutureOr<TResponse> Function(
    TRequest request,
    WorkflowContext context,
    CancellationToken cancellationToken,
  )
  handler;

  @override
  void configureProtocol(ProtocolBuilder builder) {
    builder.acceptsMessage<ExternalRequest<TRequest, TResponse>>();
    builder.requests(port);
  }

  @override
  Future<TResponse> handle(
    ExternalRequest<TRequest, TResponse> message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();
    return handler(message.request, context, token);
  }
}
