import 'package:extensions/system.dart';
import '../../microsoft_agents_ai_purview/models/common/activity.dart';
import '../executor.dart';
import '../portable_value.dart';
import 'delivery_mapping.dart';
import 'message_envelope.dart';
import 'runner_context.dart';
import 'step_tracer.dart';
import '../../../activity_stubs.dart';

abstract class EdgeRunner {
  EdgeRunner();

  Future<DeliveryMapping?> chaseEdge(
    MessageEnvelope envelope,
    StepTracer? stepTracer, {
    CancellationToken? cancellationToken,
  });
}

abstract class EdgeRunner<TEdgeData> extends EdgeRunner {
  const EdgeRunner(RunnerContext runContext, TEdgeData edgeData)
    : runContext = runContext,
      edgeData = edgeData;

  final RunnerContext runContext = runContext;

  final TEdgeData edgeData = edgeData;

  Future<ExecutorProtocol> findSourceProtocol(
    String sourceId,
    StepTracer? stepTracer, {
    CancellationToken? cancellationToken,
  }) async {
    var sourceExecutor = await this.runContext
        .ensureExecutor(
          sourceId,
          stepTracer,
          cancellationToken,
        )
        ;
    return sourceExecutor.protocol;
  }

  Future<Type?> getMessageRuntimeType(
    MessageEnvelope envelope,
    StepTracer? stepTracer, {
    CancellationToken? cancellationToken,
  }) async {
    if (envelope.message is PortableValue) {
      final PortableValue = envelope.message as PortableValue;
      if (envelope.sourceId == null) {
        return null;
      }
      var protocol = await this
          .findSourceProtocolAsync(
            envelope.sourceId,
            stepTracer,
            cancellationToken,
          )
          ;
      return protocol.sendTypeTranslator.mapTypeId(PortableValue.typeId);
    }
    return envelope.message.runtimeType;
  }

  static bool canHandle(Executor target, Type? runtimeType) {
    return runtimeType != null
        ? target.canHandle(runtimeType)
        : target.router.hasCatchAll;
  }

  Future<bool> canHandleAsync(
    String candidateTargetId,
    Type? runtimeType,
    StepTracer? stepTracer, {
    CancellationToken? cancellationToken,
  }) async {
    var candidateTarget = await this.runContext
        .ensureExecutor(
          candidateTargetId,
          stepTracer,
          cancellationToken,
        )
        ;
    return canHandle(candidateTarget, runtimeType);
  }

  Activity? startActivity() {
    return this.runContext.telemetryContext.startEdgeGroupProcessActivity();
  }
}

abstract class StatefulEdgeRunner {
  Future<PortableValue> exportState();
  Future importState(PortableValue state);
}
