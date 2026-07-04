import 'package:extensions/ai.dart';

import '../../../abstractions/agent_session_state_bag.dart';
import 'tool_approval_rule.dart';

/// Represents the persisted state of standing tool approval rules, stored in
/// the session's [AgentSessionStateBag].
class ToolApprovalState {
  ToolApprovalState();

  /// List of standing approval rules.
  List<ToolApprovalRule> rules = [];

  /// List of collected approval responses that are pending injection into the
  /// next inbound call to the inner agent.
  List<ToolApprovalResponseContent> collectedApprovalResponses = [];

  /// List of queued tool approval requests that have not yet been presented to
  /// the caller.
  List<ToolApprovalRequestContent> queuedApprovalRequests = [];

  /// Encodes the durable part of this state (the standing rules) to a
  /// JSON-compatible map so the session bag can serialize it.
  ///
  /// The in-flight approval content ([collectedApprovalResponses] and
  /// [queuedApprovalRequests]) is transient — it only exists mid-turn while
  /// an approval round-trip is pending — and is intentionally not persisted.
  Map<String, Object?> toJson() => {
    'rules': [for (final rule in rules) rule.toJson()],
  };

  /// Rebuilds the state from a raw JSON-decoded value produced by [toJson].
  /// The transient in-flight approval lists start empty.
  static ToolApprovalState fromJson(Object? json) {
    final state = ToolApprovalState();
    if (json is Map) {
      state.rules = [
        for (final entry in json['rules'] as List? ?? const [])
          if (entry is Map)
            ToolApprovalRule.fromJson(entry.cast<String, Object?>()),
      ];
    }
    return state;
  }
}
