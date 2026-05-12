import '../executor.dart';
import 'delivery_mapping.dart';
import 'edge_runner.dart';
import 'message_envelope.dart';
import 'step_tracer.dart';

/// Routes an external response envelope back to the executor that issued the
/// corresponding request.
final class ResponseEdgeRunner extends EdgeRunner {
  /// Creates a [ResponseEdgeRunner] for [executorId] linked to [portId].
  ResponseEdgeRunner({
    required this.executorId,
    required this.portId,
    required this.executor,
  });

  /// Gets the executor that will receive the response.
  final String executorId;

  /// Gets the port identifier this runner is bound to.
  final String portId;

  /// Gets the bound executor instance.
  final Executor<dynamic, dynamic> executor;

  @override
  DeliveryMapping? chaseEdge(
    MessageEnvelope envelope, {
    IStepTracer? stepTracer,
  }) {
    if (!envelope.isExternal) return null;
    if (executor.canAccept(envelope.message?.runtimeType ?? Null)) {
      return DeliveryMapping.single(envelope, executor);
    }
    return null;
  }
}
