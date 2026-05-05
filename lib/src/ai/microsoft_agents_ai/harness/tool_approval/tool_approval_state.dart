import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';
import 'tool_approval_rule.dart';

/// Represents the persisted state of standing tool approval rules, stored in
/// the session's [AgentSessionStateBag].
class ToolApprovalState {
  ToolApprovalState();

  /// Gets or sets the list of standing approval rules.
  List<ToolApprovalRule> rules;

  /// Gets or sets the list of collected approval responses (both auto-approved
  /// and user-approved) that are pending injection into the next inbound call
  /// to the inner agent.
  ///
  /// Remarks: Responses are collected during a queue cycle: when the inner
  /// agent returns multiple tool approval requests, auto-approved ones and
  /// user-approved ones are accumulated here. Once all queued requests are
  /// resolved, the collected responses are injected alongside the caller's
  /// messages so the inner agent receives all tool responses together.
  List<ToolApprovalResponseContent> collectedApprovalResponses;

  /// Gets or sets the list of queued tool approval requests that have not yet
  /// been presented to the caller.
  ///
  /// Remarks: When the inner agent returns multiple unapproved tool approval
  /// requests, only the first is returned to the caller. The remaining requests
  /// are stored here and presented one at a time on subsequent calls, allowing
  /// the caller's "always approve" rules to take effect on later items in the
  /// same batch.
  List<ToolApprovalRequestContent> queuedApprovalRequests;
}
