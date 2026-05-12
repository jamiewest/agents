import 'package:extensions/system.dart';
import 'package:opentelemetry/api.dart';

import 'checkpoint_info.dart';
import 'checkpoint_manager.dart';
import 'observability/activity_extensions.dart';
import 'observability/workflow_telemetry_options.dart';
import 'run.dart';
import 'run_status.dart';
import 'streaming_run.dart';
import 'workflow.dart';
import 'workflow_execution_environment.dart';

const _defaultSourceName = 'microsoft.agents.ai.workflows';

/// Adds OpenTelemetry instrumentation to a [WorkflowExecutionEnvironment].
extension OpenTelemetryWorkflowExecutionEnvironmentExtensions
    on WorkflowExecutionEnvironment {
  /// Returns a new execution environment that wraps each run in an
  /// OpenTelemetry span.
  ///
  /// [sourceName] sets the instrumentation library name used by the tracer
  /// (defaults to `'microsoft.agents.ai.workflows'`). Pass a pre-configured
  /// [Tracer] via [tracer] to override the global tracer provider lookup.
  /// Use [options] to suppress specific span types.
  WorkflowExecutionEnvironment withOpenTelemetry({
    String? sourceName,
    Tracer? tracer,
    WorkflowTelemetryOptions? options,
  }) =>
      _OtelWorkflowExecutionEnvironment(
        inner: this,
        tracer: tracer ??
            globalTracerProvider.getTracer(
              sourceName ?? _defaultSourceName,
            ),
        options: options ?? WorkflowTelemetryOptions(),
      );
}

// ── instrumented wrapper ──────────────────────────────────────────────────────

final class _OtelWorkflowExecutionEnvironment
    implements WorkflowExecutionEnvironment {
  _OtelWorkflowExecutionEnvironment({
    required WorkflowExecutionEnvironment inner,
    required Tracer tracer,
    required WorkflowTelemetryOptions options,
  }) : _inner = inner,
       _tracer = tracer,
       _options = options;

  final WorkflowExecutionEnvironment _inner;
  final Tracer _tracer;
  final WorkflowTelemetryOptions _options;

  @override
  Future<Run> runAsync<TInput>(
    Workflow workflow,
    TInput input, {
    CheckpointManager? checkpointManager,
    String? sessionId,
    CancellationToken? cancellationToken,
  }) async {
    if (_options.disableWorkflowRun) {
      return _inner.runAsync(
        workflow,
        input,
        checkpointManager: checkpointManager,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
      );
    }
    final span = _tracer.startWorkflowInvokeSpan(
      sessionId ?? '',
      workflowName: workflow.name,
    );
    try {
      final run = await _inner.runAsync(
        workflow,
        input,
        checkpointManager: checkpointManager,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
      );
      span.setSessionId(run.sessionId);
      final status = await run.getStatusAsync();
      if (status == RunStatus.ended) {
        span.endSuccessfully();
      } else {
        span.end();
      }
      return run;
    } catch (error, stack) {
      span.recordWorkflowError(error, stack);
      span.end();
      rethrow;
    }
  }

  @override
  Future<StreamingRun> streamAsync<TInput>(
    Workflow workflow, {
    TInput? input,
    CheckpointManager? checkpointManager,
    String? sessionId,
    CancellationToken? cancellationToken,
  }) async {
    if (_options.disableWorkflowRun) {
      return _inner.streamAsync(
        workflow,
        input: input,
        checkpointManager: checkpointManager,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
      );
    }
    final span = _tracer.startWorkflowInvokeSpan(
      sessionId ?? '',
      workflowName: workflow.name,
    );
    try {
      final run = await _inner.streamAsync(
        workflow,
        input: input,
        checkpointManager: checkpointManager,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
      );
      span.setSessionId(run.sessionId);
      span.endSuccessfully();
      return run;
    } catch (error, stack) {
      span.recordWorkflowError(error, stack);
      span.end();
      rethrow;
    }
  }

  @override
  Future<StreamingRun> openStreamAsync(
    Workflow workflow, {
    String? sessionId,
    CancellationToken? cancellationToken,
  }) =>
      streamAsync<Object?>(
        workflow,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
      );

  @override
  Future<Run> resumeAsync(
    Workflow workflow,
    CheckpointInfo checkpoint,
    CheckpointManager checkpointManager, {
    String? sessionId,
    CancellationToken? cancellationToken,
  }) async {
    if (_options.disableWorkflowRun) {
      return _inner.resumeAsync(
        workflow,
        checkpoint,
        checkpointManager,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
      );
    }
    final span = _tracer.startWorkflowInvokeSpan(
      sessionId ?? checkpoint.checkpointId,
      workflowName: workflow.name,
    );
    try {
      final run = await _inner.resumeAsync(
        workflow,
        checkpoint,
        checkpointManager,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
      );
      span.setSessionId(run.sessionId);
      span.endSuccessfully();
      return run;
    } catch (error, stack) {
      span.recordWorkflowError(error, stack);
      span.end();
      rethrow;
    }
  }

  @override
  Future<StreamingRun> resumeStreamAsync(
    Workflow workflow,
    CheckpointInfo checkpoint,
    CheckpointManager checkpointManager, {
    String? sessionId,
    CancellationToken? cancellationToken,
  }) async {
    if (_options.disableWorkflowRun) {
      return _inner.resumeStreamAsync(
        workflow,
        checkpoint,
        checkpointManager,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
      );
    }
    final span = _tracer.startWorkflowInvokeSpan(
      sessionId ?? checkpoint.checkpointId,
      workflowName: workflow.name,
    );
    try {
      final run = await _inner.resumeStreamAsync(
        workflow,
        checkpoint,
        checkpointManager,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
      );
      span.setSessionId(run.sessionId);
      span.endSuccessfully();
      return run;
    } catch (error, stack) {
      span.recordWorkflowError(error, stack);
      span.end();
      rethrow;
    }
  }
}
