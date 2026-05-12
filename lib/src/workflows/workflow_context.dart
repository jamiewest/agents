import 'package:extensions/system.dart';

import 'external_request.dart';
import 'external_response.dart';
import 'request_port.dart';

/// Context supplied to an executor while handling a workflow message.
abstract interface class WorkflowContext {
  /// Gets the identifier of the executor currently being invoked.
  String get executorId;

  /// Sends [message] to another executor, or the workflow router.
  Future<void> sendMessage<T>(
    T message, {
    String? targetExecutorId,
    CancellationToken? cancellationToken,
  });

  /// Emits [output] as workflow output.
  Future<void> yieldOutput<T>(T output, {CancellationToken? cancellationToken});

  /// Sends an external request through [port].
  Future<ExternalResponse<TResponse>> sendRequest<TRequest, TResponse>(
    RequestPort<TRequest, TResponse> port,
    TRequest request, {
    CancellationToken? cancellationToken,
  });
}

/// Minimal in-memory workflow context used by tests and lightweight executors.
class CollectingWorkflowContext implements WorkflowContext {
  /// Creates a collecting workflow context for [executorId].
  CollectingWorkflowContext(this.executorId);

  /// Gets sent messages.
  final List<Object?> sentMessages = <Object?>[];

  /// Gets yielded outputs.
  final List<Object?> outputs = <Object?>[];

  /// Gets external requests.
  final List<ExternalRequest<Object?, Object?>> requests =
      <ExternalRequest<Object?, Object?>>[];

  @override
  final String executorId;

  @override
  Future<void> sendMessage<T>(
    T message, {
    String? targetExecutorId,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    sentMessages.add(message);
  }

  @override
  Future<void> yieldOutput<T>(
    T output, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    outputs.add(output);
  }

  @override
  Future<ExternalResponse<TResponse>> sendRequest<TRequest, TResponse>(
    RequestPort<TRequest, TResponse> port,
    TRequest request, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final externalRequest = ExternalRequest<TRequest, TResponse>(
      requestId: '${requests.length + 1}',
      port: port,
      request: request,
    );
    requests.add(externalRequest as ExternalRequest<Object?, Object?>);
    return ExternalResponse<TResponse>(
      requestId: externalRequest.requestId,
      port: port.toDescriptor(),
      response: null as TResponse,
    );
  }
}
