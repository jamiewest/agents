import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';

/// Represents the state of the agent's operating mode, stored in the
/// session's [AgentSessionStateBag].
class AgentModeState {
  AgentModeState();

  /// Gets or sets the current operating mode of the agent.
  String currentMode = "plan";

  /// Gets or sets the previous mode before the last external change, if a mode
  /// change notification is pending. When non-null, indicates that the mode was
  /// changed externally and a notification should be injected.
  String? previousModeForNotification;
}
