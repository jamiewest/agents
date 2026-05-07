import 'package:extensions/system.dart';

import '../external_request.dart';
import '../external_response.dart';
import '../request_port.dart';
import '../workflow_context.dart';
import 'message_envelope.dart';

/// Workflow context for a single executor invocation.
class StepContext implements WorkflowContext {
  /// Creates a step context.
  StepContext(this.executorId);

  final List<MessageEnvelope> _sentMessages = <MessageEnvelope>[];
  final List<Object?> _outputs = <Object?>[];
  final List<ExternalRequest<Object?, Object?>> _requests =
      <ExternalRequest<Object?, Object?>>[];

  /// Gets messages explicitly sent by the executor.
  List<MessageEnvelope> get sentMessages =>
      List<MessageEnvelope>.unmodifiable(_sentMessages);

  /// Gets outputs yielded by the executor.
  List<Object?> get outputs => List<Object?>.unmodifiable(_outputs);

  /// Gets external requests issued by the executor.
  List<ExternalRequest<Object?, Object?>> get requests =>
      List<ExternalRequest<Object?, Object?>>.unmodifiable(_requests);

  @override
  final String executorId;

  @override
  Future<void> sendMessage<T>(
    T message, {
    String? targetExecutorId,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    if (targetExecutorId == null || targetExecutorId.isEmpty) {
      throw ArgumentError.value(
        targetExecutorId,
        'targetExecutorId',
        'A target executor is required for explicit sends.',
      );
    }
    _sentMessages.add(
      MessageEnvelope(
        sourceExecutorId: executorId,
        targetExecutorId: targetExecutorId,
        message: message,
      ),
    );
  }

  @override
  Future<void> yieldOutput<T>(
    T output, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    _outputs.add(output);
  }

  @override
  Future<ExternalResponse<TResponse>> sendRequest<TRequest, TResponse>(
    RequestPort<TRequest, TResponse> port,
    TRequest request, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final externalRequest = ExternalRequest<TRequest, TResponse>(
      requestId: '$executorId-${_requests.length + 1}',
      port: port,
      request: request,
    );
    _requests.add(externalRequest as ExternalRequest<Object?, Object?>);
    return ExternalResponse<TResponse>(
      requestId: externalRequest.requestId,
      port: port.toDescriptor(),
      response: null as TResponse,
    );
  }
}
