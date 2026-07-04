import '../../../abstractions/agent_session_state_bag.dart';

/// Represents the state of the agent's operating mode, stored in the
/// session's [AgentSessionStateBag].
class AgentModeState {
  AgentModeState();

  /// Current operating mode of the agent.
  String currentMode = "plan";

  /// Previous mode before the last external change, if a mode change
  /// notification is pending.
  ///
  /// When non-null, indicates that the mode was changed externally and a
  /// notification should be injected.
  String? previousModeForNotification;

  /// Encodes this state to a JSON-compatible map so the session bag can
  /// serialize it.
  Map<String, Object?> toJson() => {
    'currentMode': currentMode,
    if (previousModeForNotification != null)
      'previousModeForNotification': previousModeForNotification,
  };

  /// Rebuilds the state from a raw JSON-decoded value produced by [toJson].
  static AgentModeState fromJson(Object? json) {
    final state = AgentModeState();
    if (json is Map) {
      state.currentMode = json['currentMode'] as String? ?? 'plan';
      state.previousModeForNotification =
          json['previousModeForNotification'] as String?;
    }
    return state;
  }
}
