import 'package:extensions/ai.dart';

/// Shared helpers for deciding whether a tool call is subject to human
/// approval.
///
/// [FunctionInvokingChatClient] has an all-or-nothing behavior for approvals:
/// when any tool in a response is an [ApprovalRequiredAIFunction], every
/// [FunctionCallContent] in that response is converted to a
/// [ToolApprovalRequestContent], including calls to tools that do not require
/// approval. Several decorators therefore need to tell the two apart, and they
/// must agree on the answer.
///
/// The rule is deliberately closed by default: a tool counts as not requiring
/// approval only when it is a known tool that is explicitly not an
/// [ApprovalRequiredAIFunction]. Anything else, including a tool name that does
/// not appear in the available tools at all, is treated as requiring approval.
abstract final class ApprovalRequirement {
  /// Builds the set of tool names that do not require approval, from the tools
  /// available to this turn: [ChatOptions.tools] together with
  /// [FunctionInvokingChatClient.additionalTools].
  ///
  /// [client] is the decorator requesting the set, used to locate the
  /// [FunctionInvokingChatClient] below it in the pipeline.
  static Set<String> getApprovalNotRequiredToolNames(
    ChatClient client,
    ChatOptions? options,
  ) {
    final functionInvoking = client.getService<FunctionInvokingChatClient>();

    final allTools = <AITool>[
      ...?options?.tools,
      ...?functionInvoking?.additionalTools,
    ];

    return {
      for (final tool in allTools.whereType<AIFunction>())
        if (!requiresApproval(tool)) tool.name,
    };
  }

  /// Returns `true` when [function] is (or wraps) an
  /// [ApprovalRequiredAIFunction].
  static bool requiresApproval(AIFunction function) {
    AIFunction current = function;
    while (true) {
      if (current is ApprovalRequiredAIFunction) {
        return true;
      }
      if (current is DelegatingAIFunction) {
        current = current.innerFunction;
        continue;
      }
      return false;
    }
  }

  /// Determines whether [toolCall] targets a known tool that does not require
  /// approval.
  ///
  /// Returns `true` only when [toolCall] is a function call whose tool is known
  /// and explicitly does not require approval; otherwise `false`, which
  /// includes unknown tools and non-function tool calls.
  static bool isApprovalNotRequired(
    Object? toolCall,
    Set<String> approvalNotRequiredToolNames,
  ) {
    // `FunctionCallContent` does not subtype `ToolCallContent` in the
    // `extensions` port, so the call arrives as a `dynamic` shape.
    final dynamic call = toolCall;
    if (call is! FunctionCallContent) {
      return false;
    }
    return approvalNotRequiredToolNames.contains(call.name);
  }
}
