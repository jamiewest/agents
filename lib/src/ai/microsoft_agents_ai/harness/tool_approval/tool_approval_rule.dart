/// Represents a standing approval rule for automatically approving tool calls
/// without requiring explicit user approval each time.
///
/// Remarks: A rule can match tool calls in two ways: Tool-level : When
/// [Arguments] is `null`, all calls to the tool identified by [ToolName] are
/// auto-approved. Tool+arguments : When [Arguments] is non-null, only calls
/// to the specified tool with exactly matching argument values are
/// auto-approved.
class ToolApprovalRule {
  ToolApprovalRule();

  /// Gets or sets the name of the tool function that this rule applies to.
  String toolName = '';

  /// Gets or sets the specific argument values that must match for this rule to
  /// apply. When `null`, the rule applies to all invocations of the tool
  /// regardless of arguments.
  ///
  /// Remarks: Argument values are stored as their JSON-serialized String
  /// representations for reliable comparison.
  Map<String, String>? arguments;
}
