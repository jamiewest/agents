import '../../../abstractions/agent_session_state_bag.dart';
import 'background_agents_provider.dart';
import 'background_task_info.dart';

/// Represents the serializable state of background tasks managed by the
/// [BackgroundAgentsProvider], stored in the session's [AgentSessionStateBag].
class BackgroundAgentState {
  BackgroundAgentState();

  /// Next ID to assign to a new background task.
  int nextTaskId = 1;

  /// Gets the list of background task metadata entries.
  List<BackgroundTaskInfo> tasks = [];

  /// Encodes this state to a JSON-compatible map so the session bag can
  /// serialize it.
  Map<String, Object?> toJson() => {
    'nextTaskId': nextTaskId,
    'tasks': [for (final task in tasks) task.toJson()],
  };

  /// Rebuilds the state from a raw JSON-decoded value produced by [toJson].
  static BackgroundAgentState fromJson(Object? json) {
    final state = BackgroundAgentState();
    if (json is Map) {
      state.nextTaskId = (json['nextTaskId'] as num?)?.toInt() ?? 1;
      state.tasks = [
        for (final entry in json['tasks'] as List? ?? const [])
          if (entry is Map)
            BackgroundTaskInfo.fromJson(entry.cast<String, Object?>()),
      ];
    }
    return state;
  }
}
