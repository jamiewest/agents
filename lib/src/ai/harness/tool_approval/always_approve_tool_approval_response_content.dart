import 'package:extensions/ai.dart';

/// Wraps a [ToolApprovalResponseContent] with additional "always approve"
/// settings, enabling the [ToolApprovalAgent] middleware to record standing
/// approval rules so that future matching tool calls are auto-approved without
/// user interaction.
class AlwaysApproveToolApprovalResponseContent extends AIContent {
  /// Initializes a new instance of the
  /// [AlwaysApproveToolApprovalResponseContent] class.
  AlwaysApproveToolApprovalResponseContent(
    ToolApprovalResponseContent? innerResponse,
    this.alwaysApproveTool,
    this.alwaysApproveToolWithArguments,
  ) : innerResponse =
          innerResponse ?? (throw ArgumentError.notNull('innerResponse'));

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
