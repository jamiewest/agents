import 'package:extensions/ai.dart';

import 'always_approve_tool_approval_response_content.dart';

/// Provides extension methods on [ToolApprovalRequestContent] for creating
/// [AlwaysApproveToolApprovalResponseContent] instances that instruct the
/// [ToolApprovalAgent] middleware to record standing approval rules.
extension ToolApprovalRequestContentExtensions on ToolApprovalRequestContent? {
  /// Creates an approved [AlwaysApproveToolApprovalResponseContent] that also
  /// instructs the middleware to always approve future calls to the same tool,
  /// regardless of the arguments provided.
  AlwaysApproveToolApprovalResponseContent createAlwaysApproveToolResponse({
    String? reason,
  }) {
    final request = this ?? (throw ArgumentError.notNull('request'));
    return AlwaysApproveToolApprovalResponseContent(
      request.createResponse(true, reason: reason),
      true,
      false,
    );
  }

  /// Creates an approved [AlwaysApproveToolApprovalResponseContent] that also
  /// instructs the middleware to always approve future calls to the same tool
  /// with the exact same arguments.
  AlwaysApproveToolApprovalResponseContent
  createAlwaysApproveToolWithArgumentsResponse({String? reason}) {
    final request = this ?? (throw ArgumentError.notNull('request'));
    return AlwaysApproveToolApprovalResponseContent(
      request.createResponse(true, reason: reason),
      false,
      true,
    );
  }
}
