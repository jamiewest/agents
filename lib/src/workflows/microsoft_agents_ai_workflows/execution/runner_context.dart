import 'package:extensions/system.dart';
import '../observability/workflow_telemetry_context.dart';
import '../workflow_context.dart';
import '../workflow_event.dart';
import 'external_request_sink.dart';
import 'step_context.dart';
import 'step_tracer.dart';
import 'super_step_join_context.dart';

abstract class RunnerContext
    implements ExternalRequestSink, SuperStepJoinContext {
  WorkflowTelemetryContext get telemetryContext;
  Future addEvent(
    WorkflowEvent workflowEvent, {
    CancellationToken? cancellationToken,
  });
  Future sendMessage(
    String sourceId,
    Object message, {
    String? targetId,
    CancellationToken? cancellationToken,
  });
  Future<StepContext> advance({CancellationToken? cancellationToken});
  WorkflowContext bindWorkflowContext(
    String executorId, {
    Map<String, String>? traceContext,
  });
  Future<Executor> ensureExecutor(
    String executorId,
    StepTracer? tracer, {
    CancellationToken? cancellationToken,
  });
}
