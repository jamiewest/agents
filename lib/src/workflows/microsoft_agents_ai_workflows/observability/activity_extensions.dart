import 'package:opentelemetry/api.dart';

import 'activity_names.dart';
import 'tags.dart';

/// Extension methods on [Tracer] for creating workflow-specific spans.
extension WorkflowTracerExtensions on Tracer {
  /// Starts a span covering a full workflow invocation.
  Span startWorkflowInvokeSpan(
    String sessionId, {
    String? workflowName,
    Context? context,
  }) =>
      startSpan(
        ActivityNames.workflowInvoke,
        kind: SpanKind.internal,
        context: context ?? Context.current,
        attributes: [
          Attribute.fromString(Tags.sessionId, sessionId),
          if (workflowName != null)
            Attribute.fromString(Tags.workflowName, workflowName),
        ],
      );

  /// Starts a span covering a workflow session lifecycle.
  Span startWorkflowSessionSpan(
    String sessionId, {
    Context? context,
  }) =>
      startSpan(
        ActivityNames.workflowSession,
        kind: SpanKind.internal,
        context: context ?? Context.current,
        attributes: [Attribute.fromString(Tags.sessionId, sessionId)],
      );

  /// Starts a span covering a single executor invocation.
  Span startExecutorProcessSpan(
    String executorId, {
    String? executorType,
    Context? context,
  }) =>
      startSpan(
        ActivityNames.executorProcess,
        kind: SpanKind.internal,
        context: context ?? Context.current,
        attributes: [
          Attribute.fromString(Tags.executorId, executorId),
          if (executorType != null)
            Attribute.fromString(Tags.executorType, executorType),
        ],
      );

  /// Starts a span covering a message send between executors.
  Span startMessageSendSpan(
    String? sourceExecutorId,
    String? targetExecutorId, {
    Context? context,
  }) =>
      startSpan(
        ActivityNames.messageSend,
        kind: SpanKind.internal,
        context: context ?? Context.current,
        attributes: [
          if (sourceExecutorId != null)
            Attribute.fromString(Tags.messageSourceId, sourceExecutorId),
          if (targetExecutorId != null)
            Attribute.fromString(Tags.messageTargetId, targetExecutorId),
        ],
      );
}

/// Extension methods on [Span] for workflow-specific attribute and status
/// helpers.
extension WorkflowSpanExtensions on Span {
  /// Sets the session ID attribute.
  void setSessionId(String sessionId) =>
      setAttribute(Attribute.fromString(Tags.sessionId, sessionId));

  /// Sets the executor ID attribute.
  void setExecutorId(String executorId) =>
      setAttribute(Attribute.fromString(Tags.executorId, executorId));

  /// Sets the workflow name attribute.
  void setWorkflowName(String name) =>
      setAttribute(Attribute.fromString(Tags.workflowName, name));

  /// Records [error] as an exception and sets [StatusCode.error].
  void recordWorkflowError(Object error, [StackTrace? stackTrace]) {
    if (stackTrace != null) {
      recordException(error, stackTrace: stackTrace);
    } else {
      recordException(error);
    }
    setStatus(StatusCode.error, error.toString());
  }

  /// Sets [StatusCode.ok] and ends the span.
  void endSuccessfully() {
    setStatus(StatusCode.ok);
    end();
  }

  /// Sets [StatusCode.error] with [description] and ends the span.
  void endWithError(String description) {
    setStatus(StatusCode.error, description);
    end();
  }
}
