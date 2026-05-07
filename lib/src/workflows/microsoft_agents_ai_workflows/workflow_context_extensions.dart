import 'package:extensions/system.dart';

import 'external_response.dart';
import 'request_port.dart';
import 'workflow_context.dart';

/// Extension methods for working with [WorkflowContext] instances.
extension WorkflowContextExtensions on WorkflowContext {
  /// Sends [message] directly to [targetExecutorId].
  Future<void> sendTo<TMessage>(
    String targetExecutorId,
    TMessage message, {
    CancellationToken? cancellationToken,
  }) => sendMessage<TMessage>(
    message,
    targetExecutorId: targetExecutorId,
    cancellationToken: cancellationToken,
  );

  /// Emits [output] as workflow output.
  Future<void> yieldValue<TOutput>(
    TOutput output, {
    CancellationToken? cancellationToken,
  }) => yieldOutput<TOutput>(output, cancellationToken: cancellationToken);

  /// Requests external information through [port].
  Future<ExternalResponse<TResponse>> requestInfo<TRequest, TResponse>(
    RequestPort<TRequest, TResponse> port,
    TRequest request, {
    CancellationToken? cancellationToken,
  }) => sendRequest<TRequest, TResponse>(
    port,
    request,
    cancellationToken: cancellationToken,
  );
}
