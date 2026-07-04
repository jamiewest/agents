import 'package:extensions/ai.dart';

import '../../../json_stubs.dart';

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
  /// Each function receives a [FunctionCallContent] representing the tool
  /// call that requires approval and returns a `Future<bool>` that resolves
  /// to `true` to auto-approve the call, or `false` to continue evaluating
  /// the next rule.
  ///
  /// Auto-approval rules are evaluated after standing rules (derived from
  /// prior user approvals) but before prompting the user. Rules are evaluated
  /// in order; the first rule returning `true` causes the function call to be
  /// auto-approved.
  Iterable<Future<bool> Function(FunctionCallContent functionCall)>?
  autoApprovalRules;
}
