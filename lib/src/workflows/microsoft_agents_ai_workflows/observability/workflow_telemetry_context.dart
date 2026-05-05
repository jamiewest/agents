import '../../microsoft_agents_ai_purview/models/common/activity.dart';
import 'activity_names.dart';
import 'tags.dart';
import 'workflow_telemetry_options.dart';
import '../../../json_stubs.dart';
import '../../../activity_stubs.dart';

/// Internal context for workflow telemetry, holding the enabled state and
/// configuration options.
class WorkflowTelemetryContext {
  /// Initializes a new instance of the [WorkflowTelemetryContext] class with
  /// telemetry enabled.
  ///
  /// [options] The telemetry options.
  ///
  /// [activitySource] An optional activity source to use. If provided, this
  /// activity source will be used directly and the caller retains ownership
  /// (responsible for disposal). If `null`, the shared default activity source
  /// will be used.
  WorkflowTelemetryContext({WorkflowTelemetryOptions? options = null, ActivitySource? activitySource = null, }) {
    this.isEnabled = true;
    this.options = options;
    this.activitySource = activitySource ?? s_defaultActivitySource;
  }

  static final ActivitySource s_defaultActivitySource = new(DefaultSourceName);

  /// Gets a shared instance representing disabled telemetry.
  static final WorkflowTelemetryContext disabled;

  /// Gets a value indicating whether telemetry is enabled.
  late final bool isEnabled;

  /// Gets the telemetry options.
  late final WorkflowTelemetryOptions options;

  /// Gets the activity source used for creating telemetry spans.
  late final ActivitySource activitySource;

  /// Starts an activity if telemetry is enabled, otherwise returns null.
  ///
  /// Returns: An activity if telemetry is enabled and the activity is sampled,
  /// otherwise null.
  ///
  /// [name] The activity name.
  ///
  /// [kind] The activity kind.
  Activity? startActivity(String name, {ActivityKind? kind, }) {
    if (!this.isEnabled) {
      return null;
    }
    return this.activitySource.startActivity(name, kind);
  }

  /// Starts a workflow build activity if enabled.
  ///
  /// Returns: An activity if workflow build telemetry is enabled, otherwise
  /// null.
  Activity? startWorkflowBuildActivity() {
    if (!this.isEnabled || this.options.disableWorkflowBuild) {
      return null;
    }
    return this.activitySource.startActivity(ActivityNames.workflowBuild);
  }

  /// Starts a workflow session activity if enabled. This is the outer/parent
  /// span that represents the entire lifetime of a workflow execution (from
  /// start until stop, cancellation, or error) within the current trace.
  /// Individual run stages are typically nested within it.
  ///
  /// Returns: An activity if workflow run telemetry is enabled, otherwise null.
  Activity? startWorkflowSessionActivity() {
    if (!this.isEnabled || this.options.disableWorkflowRun) {
      return null;
    }
    return this.activitySource.startActivity(ActivityNames.WorkflowSession);
  }

  /// Starts a workflow run activity if enabled. This represents a single
  /// input-to-halt cycle within a workflow session.
  ///
  /// Returns: An activity if workflow run telemetry is enabled, otherwise null.
  Activity? startWorkflowRunActivity() {
    if (!this.isEnabled || this.options.disableWorkflowRun) {
      return null;
    }
    return this.activitySource.startActivity(ActivityNames.workflowInvoke);
  }

  /// Starts an executor process activity if enabled, with all standard tags
  /// set.
  ///
  /// Returns: An activity if executor process telemetry is enabled, otherwise
  /// null.
  ///
  /// [executorId] The executor identifier.
  ///
  /// [executorType] The executor type name.
  ///
  /// [messageType] The message type name.
  ///
  /// [message] The input message. Logged only when [EnableSensitiveData] is
  /// true.
  Activity? startExecutorProcessActivity(
    String executorId,
    String? executorType,
    String messageType,
    Object? message,
  ) {
    if (!this.isEnabled || this.options.disableExecutorProcess) {
      return null;
    }
    var activity = this.activitySource.startActivity(ActivityNames.executorProcess + " " + executorId);
    if (activity == null) {
      return null;
    }
    activity.setTag(Tags.executorId, executorId)
            .setTag(Tags.executorType, executorType)
            .setTag(Tags.messageType, messageType);
    if (this.options.enableSensitiveData) {
      activity.setTag(Tags.executorInput, serializeForTelemetry(message));
    }
    return activity;
  }

  /// Sets the executor output tag on an activity when sensitive data logging is
  /// enabled.
  ///
  /// [activity] The activity to set the output on.
  ///
  /// [output] The output value to log.
  void setExecutorOutput(Activity? activity, Object? output, ) {
    if (activity != null && this.options.enableSensitiveData) {
      activity.setTag(Tags.executorOutput, serializeForTelemetry(output));
    }
  }

  /// Starts an edge group process activity if enabled.
  ///
  /// Returns: An activity if edge group process telemetry is enabled, otherwise
  /// null.
  Activity? startEdgeGroupProcessActivity() {
    if (!this.isEnabled || this.options.disableEdgeGroupProcess) {
      return null;
    }
    return this.activitySource.startActivity(ActivityNames.edgeGroupProcess);
  }

  /// Starts a message send activity if enabled, with all standard tags set.
  ///
  /// Returns: An activity if message send telemetry is enabled, otherwise null.
  ///
  /// [sourceId] The source executor identifier.
  ///
  /// [targetId] The target executor identifier, if any.
  ///
  /// [message] The message being sent. Logged only when [EnableSensitiveData]
  /// is true.
  Activity? startMessageSendActivity(String sourceId, String? targetId, Object? message, ) {
    if (!this.isEnabled || this.options.disableMessageSend) {
      return null;
    }
    var activity = this.activitySource.startActivity(
      ActivityNames.messageSend,
      ActivityKind.producer,
    );
    if (activity == null) {
      return null;
    }
    activity.setTag(Tags.messageSourceId, sourceId);
    if (targetId != null) {
      activity.setTag(Tags.messageTargetId, targetId);
    }
    if (this.options.enableSensitiveData) {
      activity.setTag(Tags.messageContent, serializeForTelemetry(message));
    }
    return activity;
  }

  static String? serializeForTelemetry(Object? value) {
    if (value == null) {
      return null;
    }
    try {
      return JsonSerializer.serialize(value, value.runtimeType);
    } catch (e, s) {
      if (e is JsonException) {
        final  = e as JsonException;
        {
          return '[Unserializable: ${value.runtimeType.fullName}]';
        }
      } else {
        rethrow;
      }
    }
  }
}
