import 'package:extensions/system.dart';
import '../fan_in_edge_data.dart';
import '../observability/edge_runner_delivery_status.dart';
import '../observability/tags.dart';
import '../portable_value.dart';
import 'delivery_mapping.dart';
import 'edge_runner.dart';
import 'fan_in_edge_state.dart';
import 'message_envelope.dart';
import 'runner_context.dart';
import 'step_tracer.dart';

class FanInEdgeRunner extends EdgeRunner<FanInEdgeData> implements StatefulEdgeRunner {
  FanInEdgeRunner(RunnerContext runContext, FanInEdgeData edgeData)
      : super(runContext, edgeData);

  FanInEdgeState _state = new(edgeData);

  @override
  Future<DeliveryMapping?> chaseEdge(
    MessageEnvelope envelope,
    StepTracer? stepTracer,
    CancellationToken cancellationToken,
  ) async {
    assert(
      !envelope.isExternal,
      "FanIn edges should never be chased from external input",
    );
    var activity = this.startActivity();
    activity?
            .setTag(Tags.edgeGroupType, 'FanInEdgeRunner')
            .setTag(Tags.messageTargetId, this.edgeData.sinkId);
    if (envelope.targetId != null && this.edgeData.sinkId != envelope.targetId) {
      activity?.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.droppedTargetMismatch);
      return null;
    }
    var releasedMessages = this._state.processMessage(envelope.sourceId, envelope)?.toList();
    if (releasedMessages == null) {
      // Not ready to process yet.
            activity?.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.buffered);
      return null;
    }
    try {
      var protocolGroupings = await Future.wait(releasedMessages.map(MapProtocolsAsync))
                                              ;
      var typedEnvelopes = protocolGroupings.expand(MapRuntimeTypes);
      var target = await this.runContext.ensureExecutor(
        this.edgeData.sinkId,
        stepTracer,
        cancellationToken,
      )
                                                   ;
      var finalReleasedMessages = typedEnvelopes.where((te) => canHandle(target, te.runtimeType))
                                                                        .map((te) => te.messageEnvelope)
                                                                        .toList();
      if (finalReleasedMessages.length == 0) {
        activity?.setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus.droppedTypeMismatch);
        return null;
      }
      return deliveryMapping(finalReleasedMessages, target);
      /* TODO: unsupported node kind "unknown" */
      // async Task<(ExecutorProtocol, IGrouping<ExecutorIdentity, MessageEnvelope>)> MapProtocolsAsync(IGrouping<ExecutorIdentity, MessageEnvelope> grouping)
      //             {
        //                 ExecutorProtocol protocol = await this.FindSourceProtocolAsync(grouping.Key.Id!, stepTracer, cancellationToken);
        //                 return (protocol, grouping);
        //             }
      /* TODO: unsupported node kind "unknown" */
      // Iterable<(Type?, MessageEnvelope)> MapRuntimeTypes((ExecutorProtocol, IGrouping<ExecutorIdentity, MessageEnvelope>) input)
      //             {
        //                 (ExecutorProtocol protocol, IGrouping<ExecutorIdentity, MessageEnvelope> grouping) = input;
        //                 return grouping.Select(envelope => (ResolveEnvelopeType(envelope), envelope));
        //
        //                 Type? ResolveEnvelopeType(MessageEnvelope messageEnvelope)
        //                 {
          //                     if (messageEnvelope.Message is PortableValue PortableValue)
          //                     {
            //                         return protocol.SendTypeTranslator.MapTypeId(PortableValue.TypeId);
            //                     }
          //
          //                     return messageEnvelope.Message.GetType();
          //                 }
        //             }
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

  @override
  Future<PortableValue> exportState() {
    return new(PortableValue(this._state));
  }

  @override
  Future importState(PortableValue state) {
    if (state.isValue(importedState)) {
      this._state = importedState;
      return Future.value();
    }
    throw StateError('Unsupported exported state type: ${state.runtimeType}; ${this.edgeData.id}');
  }
}
