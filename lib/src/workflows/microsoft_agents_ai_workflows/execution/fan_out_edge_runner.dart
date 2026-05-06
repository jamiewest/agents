import 'package:extensions/system.dart';
import '../fan_out_edge_data.dart';
import '../observability/edge_runner_delivery_status.dart';
import '../observability/tags.dart';
import 'delivery_mapping.dart';
import 'message_envelope.dart';
import 'runner_context.dart';
import 'step_tracer.dart';

class FanOutEdgeRunner extends EdgeRunner<FanOutEdgeData> {
  const FanOutEdgeRunner(RunnerContext runContext, FanOutEdgeData edgeData, );

  @override
  Future<DeliveryMapping?> chaseEdge(
    MessageEnvelope envelope,
    StepTracer? stepTracer,
    CancellationToken cancellationToken,
  ) async {
    var activity = this.startActivity();
    activity?
            .setTag(Tags.edgeGroupType, 'FanOutEdgeRunner')
            .setTag(Tags.messageSourceId, this.edgeData.sourceId);
    var message = envelope.message;
    try {
      var targetIds = this.edgeData.edgeAssigner == null
                    ? this.edgeData.sinkIds
                    : this.edgeData.edgeAssigner(message, this.edgeData.sinkIds.length)
                                .map((i) => this.edgeData.sinkIds[i]);
      var result = await Future.wait(targetIds.where(IsValidTarget)
                                                            .map((tid) => this.runContext.ensureExecutor(tid, stepTracer)
                                                            .future))
                                        ;
      if (result.length == 0) {
        activity?.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.droppedTargetMismatch);
        return null;
      }
      var runtimeType = await this.getMessageRuntimeTypeAsync(
        envelope,
        stepTracer,
        cancellationToken,
      )
                                          ;
      var validTargets = result.where((t) => canHandle(t, runtimeType));
      if (!validTargets.isNotEmpty) {
        activity?.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.droppedTypeMismatch);
        return null;
      }
      activity?.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.delivered);
      return deliveryMapping(envelope, validTargets);
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
    /* TODO: unsupported node kind "unknown" */
    // bool IsValidTarget(String targetId)
    //         {
      //             return envelope.TargetId is null || targetId == envelope.TargetId;
      //         }
  }
}
