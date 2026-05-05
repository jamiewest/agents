import 'tool_approval_agent.dart';
import 'tool_approval_rule.dart';

/// Wraps a [ToolApprovalResponseContent] with additional "always approve"
/// settings, enabling the [ToolApprovalAgent] middleware to record standing
/// approval rules so that future matching tool calls are auto-approved
/// without user interaction.
///
/// Remarks: Instances of this class should not be created directly. Instead,
/// use the extension methods [String)] or [String)] on
/// [ToolApprovalRequestContent] to create instances with the appropriate
/// flags set. The [ToolApprovalAgent] middleware will unwrap the
/// [InnerResponse] to forward to the inner agent, while extracting the
/// approval settings to persist as [ToolApprovalRule] entries in the session
/// state.
class AlwaysApproveToolApprovalResponseContent extends AIContent {
  /// Initializes a new instance of the
  /// [AlwaysApproveToolApprovalResponseContent] class.
  ///
  /// [innerResponse] The underlying approval response to forward to the agent.
  ///
  /// [alwaysApproveTool] When `true`, all future calls to this tool type will
  /// be auto-approved.
  ///
  /// [alwaysApproveToolWithArguments] When `true`, all future calls to this
  /// tool type with the same arguments will be auto-approved.
  AlwaysApproveToolApprovalResponseContent(
    ToolApprovalResponseContent innerResponse,
    bool alwaysApproveTool,
    bool alwaysApproveToolWithArguments,
  ) : innerResponse = innerResponse,
      alwaysApproveTool = alwaysApproveTool,
      alwaysApproveToolWithArguments = alwaysApproveToolWithArguments {
  }

  /// Gets the underlying [ToolApprovalResponseContent] that will be forwarded
  /// to the inner agent.
  final ToolApprovalResponseContent innerResponse;

  /// Gets a value indicating whether all future calls to the same tool should
  /// be auto-approved regardless of the arguments provided.
  final bool alwaysApproveTool;

  /// Gets a value indicating whether all future calls to the same tool with the
  /// exact same arguments should be auto-approved.
  final bool alwaysApproveToolWithArguments;
}
