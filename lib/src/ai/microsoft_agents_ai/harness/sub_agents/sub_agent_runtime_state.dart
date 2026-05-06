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

  /// Gets the mapping of task IDs to their in-flight [Task] instances.
  final Map<int, Future<AgentResponse>> inFlightTasks = {};

  /// Gets the mapping of task IDs to their sub-agent [AgentSession] instances,
  /// needed for `ContinueTask`.
  final Map<int, AgentSession> subFutureSessions = {};
}
