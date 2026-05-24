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
}
