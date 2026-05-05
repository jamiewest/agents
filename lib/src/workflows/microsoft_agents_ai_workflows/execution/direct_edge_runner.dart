import 'package:extensions/system.dart';
import '../direct_edge_data.dart';
import '../observability/edge_runner_delivery_status.dart';
import '../observability/tags.dart';
import 'delivery_mapping.dart';
import 'message_envelope.dart';
import 'runner_context.dart';
import 'step_tracer.dart';

class DirectEdgeRunner extends EdgeRunner<DirectEdgeData> {
  const DirectEdgeRunner(RunnerContext runContext, DirectEdgeData edgeData, );

  @override
  Future<DeliveryMapping?> chaseEdge(
    MessageEnvelope envelope,
    StepTracer? stepTracer,
    CancellationToken cancellationToken,
  ) async  {
    var activity = this.startActivity();
    activity?
            .setTag(Tags.edgeGroupType, 'DirectEdgeRunner')
            .setTag(Tags.messageSourceId, this.edgeData.sourceId)
            .setTag(Tags.messageTargetId, this.edgeData.sinkId);
    if (envelope.targetId != null && this.edgeData.sinkId != envelope.targetId) {
      activity?.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.droppedTargetMismatch);
      return null;
    }
    var message = envelope.message;
    try {
      if (this.edgeData.condition != null && !this.edgeData.condition(message)) {
        activity?.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.droppedConditionFalse);
        return null;
      }
      var messageType = await this.getMessageRuntimeTypeAsync(
        envelope,
        stepTracer,
        cancellationToken,
      )
                                          ;
      var target = await this.runContext.ensureExecutor(
        this.edgeData.sinkId,
        stepTracer,
        cancellationToken,
      ) ;
      if (canHandle(target, messageType)) {
        activity?.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.delivered);
        return deliveryMapping(envelope, target);
      }
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
    activity?.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.droppedTypeMismatch);
    return null;
  }
}
