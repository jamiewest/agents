import 'package:agents/src/workflows/executor_instance_binding.dart';
import 'package:agents/src/workflows/function_executor.dart';
import 'package:agents/src/workflows/in_proc/in_process_execution_environment.dart';
import 'package:agents/src/workflows/observability/activity_extensions.dart';
import 'package:agents/src/workflows/observability/activity_names.dart';
import 'package:agents/src/workflows/observability/tags.dart' as workflow_tags;
import 'package:agents/src/workflows/observability/workflow_telemetry_options.dart';
import 'package:agents/src/workflows/open_telemetry_workflow_builder_extensions.dart';
import 'package:agents/src/workflows/workflow_builder.dart';
import 'package:agents/src/workflows/workflow_execution_environment.dart';
import 'package:opentelemetry/api.dart' hide SpanExporter;
import 'package:opentelemetry/sdk.dart';
import 'package:test/test.dart';

void main() {
  group('withOpenTelemetry', () {
    late _TestExporter exporter;
    late TracerProviderBase tracerProvider;
    late WorkflowExecutionEnvironment otelEnv;

    setUp(() {
      exporter = _TestExporter();
      tracerProvider = TracerProviderBase(
        processors: [SimpleSpanProcessor(exporter)],
      );
      final tracer = tracerProvider.getTracer('test');
      otelEnv = inProcExecution.withOpenTelemetry(tracer: tracer);
    });

    test('creates a workflow.invoke span for runAsync', () async {
      final exec = FunctionExecutor<String, String>(
        'echo',
        (input, ctx, ct) => input,
      );
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(exec),
      ).addOutput('echo').build();

      final run = await otelEnv.runAsync(
        workflow,
        'hello',
        sessionId: 'sess-1',
      );

      expect(run.sessionId, 'sess-1');
      expect(exporter.spans, hasLength(1));

      final span = exporter.spans.first;
      expect(span.name, ActivityNames.workflowInvoke);
      expect(span.attributes.get(workflow_tags.Tags.sessionId), 'sess-1');
    });

    test('records error status when executor throws', () async {
      final exec = FunctionExecutor<String, String>(
        'boom',
        (input, ctx, ct) => throw StateError('kaboom'),
      );
      final workflow = WorkflowBuilder(ExecutorInstanceBinding(exec)).build();

      await expectLater(
        () => otelEnv.runAsync(workflow, 'x'),
        throwsStateError,
      );

      expect(exporter.spans, hasLength(1));
      expect(exporter.spans.first.status.code, StatusCode.error);
    });

    test('disableWorkflowRun suppresses span creation', () async {
      final exec = FunctionExecutor<String, String>(
        'echo',
        (input, ctx, ct) => input,
      );
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(exec),
      ).addOutput('echo').build();

      final suppressedEnv = inProcExecution.withOpenTelemetry(
        tracer: tracerProvider.getTracer('test'),
        options: WorkflowTelemetryOptions()..disableWorkflowRun = true,
      );

      await suppressedEnv.runAsync(workflow, 'hello');

      expect(exporter.spans, isEmpty);
    });

    test('WorkflowTracerExtensions create spans with correct names', () {
      final tracer = tracerProvider.getTracer('test');

      tracer.startWorkflowInvokeSpan('s1').end();
      tracer.startWorkflowSessionSpan('s1').end();
      tracer.startExecutorProcessSpan('exec-1').end();
      tracer.startMessageSendSpan('src', 'tgt').end();

      final names = exporter.spans.map((s) => s.name).toList();
      expect(names, contains(ActivityNames.workflowInvoke));
      expect(names, contains(ActivityNames.workflowSession));
      expect(names, contains(ActivityNames.executorProcess));
      expect(names, contains(ActivityNames.messageSend));
    });
  });
}

// ── test double ───────────────────────────────────────────────────────────────

class _TestExporter extends SpanExporter {
  final List<ReadOnlySpan> spans = [];

  @override
  void export(List<ReadOnlySpan> exported) => spans.addAll(exported);

  @override
  void forceFlush() {}

  @override
  void shutdown() {}
}
