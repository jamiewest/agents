import '../../../json_stubs.dart';
import 'tool_auto_approval_rule_context.dart';

/// Options for configuring the `ToolApprovalAgent` middleware.
class ToolApprovalAgentOptions {
  /// Creates tool-approval options.
  ToolApprovalAgentOptions();

  /// The [JsonSerializerOptions] used for serializing argument values when
  /// storing rules and for persisting state.
  ///
  /// When `null`, `AgentJsonUtilities.defaultOptions` is used.
  JsonSerializerOptions? jsonSerializerOptions;

  /// A collection of heuristic functions that can automatically approve
  /// function calls that would otherwise require user approval.
  ///
  /// Each rule receives a [ToolAutoApprovalRuleContext] describing the tool
  /// call that requires approval, along with the agent, session, request
  /// messages and run options it arose from, and returns a `Future<bool>` that
  /// resolves to `true` to auto-approve the call, or `false` to continue
  /// evaluating the next rule.
  ///
  /// Auto-approval rules are evaluated after standing rules (derived from
  /// prior user approvals) but before prompting the user. Rules are evaluated
  /// in order; the first rule returning `true` causes the function call to be
  /// auto-approved.
  Iterable<ToolAutoApprovalRule>? autoApprovalRules;

  /// The maximum number of consecutive turns the `ToolApprovalAgent` may take
  /// while every approval request it surfaces is auto-approved.
  ///
  /// Each auto-approved turn re-invokes the inner agent, which is a fresh
  /// billable call, so without a cap a model that keeps requesting an
  /// auto-approved tool would loop indefinitely. On reaching the cap the agent
  /// takes one final turn without auto-approving again, so any approval
  /// request that turn surfaces goes to the caller to decide.
  ///
  /// When `null`, `ToolApprovalAgent.defaultMaxAutoApprovalIterations` is
  /// used. Must be at least 1.
  int? maxAutoApprovalIterations;
}
