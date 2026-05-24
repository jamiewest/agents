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
}
