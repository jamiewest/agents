import 'always_approve_tool_approval_response_content.dart';
import 'tool_approval_agent.dart';

/// Provides extension methods on [ToolApprovalRequestContent] for creating
/// [AlwaysApproveToolApprovalResponseContent] instances that instruct the
/// [ToolApprovalAgent] middleware to record standing approval rules.
extension ToolApprovalRequestContentExtensions on ToolApprovalRequestContent {
  /// Creates an approved [AlwaysApproveToolApprovalResponseContent] that also
  /// instructs the middleware to always approve future calls to the same tool,
  /// regardless of the arguments provided.
  ///
  /// Returns: An [AlwaysApproveToolApprovalResponseContent] wrapping an
  /// approved [ToolApprovalResponseContent] with the [AlwaysApproveTool] flag
  /// set to `true`.
  ///
  /// [request] The tool approval request to respond to.
  ///
  /// [reason] An optional reason for the approval.
  AlwaysApproveToolApprovalResponseContent createAlwaysApproveToolResponse({
    String? reason,
  }) {
    request;
    return alwaysApproveToolApprovalResponseContent(
      request.createResponse(approved: true, reason),
      alwaysApproveTool: true,
      alwaysApproveToolWithArguments: false,
    );
  }

  /// Creates an approved [AlwaysApproveToolApprovalResponseContent] that also
  /// instructs the middleware to always approve future calls to the same tool
  /// with the exact same arguments.
  ///
  /// Returns: An [AlwaysApproveToolApprovalResponseContent] wrapping an
  /// approved [ToolApprovalResponseContent] with the
  /// [AlwaysApproveToolWithArguments] flag set to `true`.
  ///
  /// [request] The tool approval request to respond to.
  ///
  /// [reason] An optional reason for the approval.
  AlwaysApproveToolApprovalResponseContent
  createAlwaysApproveToolWithArgumentsResponse({String? reason}) {
    request;
    return alwaysApproveToolApprovalResponseContent(
      request.createResponse(approved: true, reason),
      alwaysApproveTool: false,
      alwaysApproveToolWithArguments: true,
    );
  }
}
