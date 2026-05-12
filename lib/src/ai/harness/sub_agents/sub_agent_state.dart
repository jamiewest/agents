import '../../../abstractions/agent_session_state_bag.dart';
import 'sub_agents_provider.dart';
import 'sub_task_info.dart';

/// Represents the serializable state of sub-tasks managed by the
/// [SubAgentsProvider], stored in the session's [AgentSessionStateBag].
class SubAgentState {
  SubAgentState();

  /// Next ID to assign to a new sub-task.
  int nextTaskId = 1;

  /// Gets the list of sub-task metadata entries.
  List<SubTaskInfo> tasks = [];
}
