import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import 'sub_agents_provider.dart';

/// Holds non-serializable runtime references for in-flight sub-tasks within a
/// single parent session.
///
/// Remarks: Properties are marked with [JsonIgnoreAttribute] because [Task]
/// and [AgentSession] are not JSON-serializable. After deserialization (e.g.,
/// after a restart), a fresh empty instance is created and any
/// previously-running tasks are marked as [Lost] by [SubAgentsProvider].
class SubAgentRuntimeState {
  SubAgentRuntimeState();

  /// Gets the mapping of task IDs to their in-flight [Future] instances.
  final Map<int, SubAgentRuntimeTask> inFlightTasks = {};

  /// Gets the mapping of task IDs to their sub-agent [AgentSession] instances,
  /// needed for `ContinueTask`.
  final Map<int, AgentSession> subTaskSessions = {};
}

/// Tracks the completion state of a Dart [Future] while preserving the C#
/// provider's explicit task-finalization shape.
class SubAgentRuntimeTask {
  SubAgentRuntimeTask(this.task) {
    completion = task.then<void>(
      (value) {
        isCompleted = true;
        result = value;
      },
      onError: (Object error, StackTrace stackTrace) {
        isCompleted = true;
        this.error = error;
        this.stackTrace = stackTrace;
      },
    );
  }

  /// The underlying asynchronous operation.
  final Future<AgentResponse> task;

  /// Completes after [task] has either produced a result or captured an error.
  late final Future<void> completion;

  /// Whether [task] has completed.
  bool isCompleted = false;

  /// The result from a completed task, if successful.
  AgentResponse? result;

  /// The error from a completed task, if failed.
  Object? error;

  /// The stack trace from a completed task, if failed.
  StackTrace? stackTrace;
}
