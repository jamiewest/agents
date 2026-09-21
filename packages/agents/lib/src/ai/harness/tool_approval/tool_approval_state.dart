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

  /// The approval requests this agent has surfaced to the caller and is still
  /// awaiting a response for, keyed by request id.
  ///
  /// An inbound approval response is honored only when its request id appears
  /// here, so a caller cannot approve a call the harness never surfaced.
  Map<String, ToolApprovalRequestContent> surfacedApprovalRequests = {};

  /// Encodes the durable part of this state (the standing rules) to a
  /// JSON-compatible map so the session bag can serialize it.
  ///
  /// The in-flight approval content ([collectedApprovalResponses],
  /// [queuedApprovalRequests] and [surfacedApprovalRequests]) is transient —
  /// it only exists while an approval round-trip is pending — and is
  /// intentionally not persisted. A host that serializes the session between
  /// surfacing a request and receiving its response therefore cannot bind
  /// that response, which is the safe outcome: no standing rule is recorded
  /// and the response is forwarded for the approval-binding chat client to
  /// validate against its own record.
  Map<String, Object?> toJson() => {
    'rules': [for (final rule in rules) rule.toJson()],
  };

  /// Rebuilds the state from a raw JSON-decoded value produced by [toJson].
  /// The transient in-flight approval collections start empty.
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
