import 'package:extensions/system.dart';
import '../request_port.dart';
import '../observability/edge_runner_delivery_status.dart';
import '../observability/tags.dart';
import 'delivery_mapping.dart';
import 'message_envelope.dart';
import 'runner_context.dart';
import 'step_tracer.dart';

class ResponseEdgeRunner extends EdgeRunner<String> {
  const ResponseEdgeRunner(
    RunnerContext runContext,
    String executorId,
    String sinkId,
  ) : executorId = executorId;

  static ResponseEdgeRunner forPort(
    RunnerContext runContext,
    String executorId,
    RequestPort port,
  ) {
    return responseEdgeRunner(runContext, executorId, port.id);
  }

  String get executorId {
    return executorId;
  }

  @override
  Future<DeliveryMapping?> chaseEdge(
    MessageEnvelope envelope,
    StepTracer? stepTracer,
    CancellationToken cancellationToken,
  ) async {
    assert(envelope.isExternal, "Input edges should only be chased from external input");
    var activity = this.startActivity();
    activity?
            .setTag(Tags.edgeGroupType, 'ResponseEdgeRunner')
            .setTag(Tags.messageSourceId, envelope.sourceId)
            .setTag(Tags.messageTargetId, '${this.executorId}[${this.edgeData}]');
    try {
      var target = await this.findExecutorAsync(stepTracer);
      var runtimeType = await this.getMessageRuntimeTypeAsync(
        envelope,
        stepTracer,
        cancellationToken,
      ) ;
      if (canHandle(target, runtimeType)) {
        activity?.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.delivered);
        return deliveryMapping(envelope, target);
      }
      activity?.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.droppedTypeMismatch);
      return null;
    } catch (e, s) {
      if (e is Exception) {
        final  = e as Exception;
        {
          activity.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.exception);
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  Future<Executor> findExecutor(StepTracer? tracer) async {
    return await this.runContext.ensureExecutor(this.executorId, tracer);
  }
}
