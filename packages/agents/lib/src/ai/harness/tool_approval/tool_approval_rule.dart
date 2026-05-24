/// Represents a standing approval rule for automatically approving tool calls
/// without requiring explicit user approval each time.
///
/// A rule can match tool calls in two ways. At the tool level, when
/// [arguments] is `null`, all calls to the tool identified by [toolName] are
/// auto-approved. At the tool+arguments level, when [arguments] is non-null,
/// only calls to the specified tool with exactly matching argument values are
/// auto-approved.
class ToolApprovalRule {
  ToolApprovalRule({this.toolName = '', this.arguments});

  /// Name of the tool function that this rule applies to.
  String toolName;

  /// Specific argument values that must match for this rule to apply.
  ///
  /// When `null`, the rule applies to all invocations of the tool regardless
  /// of arguments. Argument values are stored as their JSON-serialized string
  /// representations for reliable comparison.
  Map<String, String>? arguments;
}
