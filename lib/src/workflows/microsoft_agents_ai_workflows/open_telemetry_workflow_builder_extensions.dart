import 'observability/workflow_telemetry_options.dart';
import 'workflow_builder.dart';
import '../../activity_stubs.dart';
import '../../func_typedefs.dart';

/// Provides extension methods for adding OpenTelemetry instrumentation to
/// [WorkflowBuilder] instances.
extension OpenTelemetryWorkflowBuilderExtensions on WorkflowBuilder {
  /// Enables OpenTelemetry instrumentation for the workflow, providing
/// comprehensive observability for workflow operations.
///
/// Remarks: This extension adds comprehensive telemetry capabilities to
/// workflows, including: Distributed tracing of workflow execution Executor
/// invocation and processing spans Edge routing and message delivery spans
/// Workflow build and validation spans Error tracking and exception details
/// By default, workflow telemetry is disabled. Call this method to enable
/// telemetry collection.
///
/// Returns: The [WorkflowBuilder] with OpenTelemetry instrumentation enabled,
/// enabling method chaining.
///
/// [builder] The [WorkflowBuilder] to which OpenTelemetry support will be
/// added.
///
/// [configure] An optional callback that provides additional configuration of
/// the [WorkflowTelemetryOptions] instance. This allows for fine-tuning
/// telemetry behavior such as enabling sensitive data collection.
///
/// [activitySource] An optional [ActivitySource] to use for telemetry. If
/// provided, this activity source will be used directly and the caller
/// retains ownership (responsible for disposal). If `null`, a shared default
/// activity source named "Microsoft.Agents.AI.Workflows" will be used.
WorkflowBuilder withOpenTelemetry({Action<WorkflowTelemetryOptions>? configure, ActivitySource? activitySource, }) {
var options = new();
configure?.invoke(options);
var context = new(options, activitySource);
builder.setTelemetryContext(context);
return builder;
 }
 }
