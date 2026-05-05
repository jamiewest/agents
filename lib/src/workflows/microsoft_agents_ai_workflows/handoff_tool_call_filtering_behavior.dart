/// Specifies the behavior for filtering [FunctionCallContent] and [Tool]
/// contents from [ChatMessage]s flowing through a handoff workflow. This can
/// be used to prevent agents from seeing external tool calls.
enum HandoffToolCallFilteringBehavior {
  /// Do not filter [FunctionCallContent] and [Tool] contents.
  none,

  /// Filter only handoff-related [FunctionCallContent] and [Tool] contents.
  handoffOnly,

  /// Filter all [FunctionCallContent] and [Tool] contents.
  all,
}
