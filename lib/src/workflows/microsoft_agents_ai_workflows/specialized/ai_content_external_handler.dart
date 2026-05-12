import 'dart:async';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../external_request.dart';
import '../request_port.dart';
import '../workflow_context.dart';

/// Manages pending AI content requests and matches them to external responses.
///
/// In intercepted mode, [handleAsync] wraps each request in an
/// [ExternalRequest] and forwards it via [WorkflowContext.sendMessage] so
/// that the workflow runtime can deliver it to an external consumer. The
/// returned [Future] completes when [tryDeliverResponse] is called with
/// the matching response.
class AIContentExternalHandler<TRequestContent extends AIContent,
    TResponseContent extends AIContent> {
  /// Creates an [AIContentExternalHandler] with the optional [port].
  AIContentExternalHandler({this.port, this.intercepted = false});

  /// The request port used when [intercepted] is `false`.
  final RequestPort<TRequestContent, TResponseContent>? port;

  /// Whether to route requests through [WorkflowContext.sendMessage].
  final bool intercepted;

  final Map<String, Completer<TResponseContent>> _pending = {};

  /// Returns `true` when there are requests awaiting responses.
  bool get hasPendingRequests => _pending.isNotEmpty;

  /// Registers [content] as a pending external request and, in intercepted
  /// mode, sends it via [context].
  ///
  /// The returned [Future] completes when [tryDeliverResponse] is called
  /// with [requestId].
  Future<TResponseContent> handleAsync(
    String requestId,
    TRequestContent content,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();

    final completer = Completer<TResponseContent>();
    _pending[requestId] = completer;

    if (intercepted) {
      final effectivePort =
          port ??
          RequestPort<TRequestContent, TResponseContent>(
            requestId,
            description: '$TRequestContent external handler',
          );
      final request = ExternalRequest<TRequestContent, TResponseContent>(
        requestId: requestId,
        port: effectivePort,
        request: content,
      );
      await context.sendMessage<ExternalRequest<TRequestContent, TResponseContent>>(
        request,
        cancellationToken: token,
      );
    }

    return completer.future;
  }

  /// Delivers [response] to the pending request identified by [requestId].
  ///
  /// Returns `true` if a matching pending request was found.
  bool tryDeliverResponse(String requestId, TResponseContent response) {
    final completer = _pending.remove(requestId);
    if (completer == null) return false;
    completer.complete(response);
    return true;
  }
}
