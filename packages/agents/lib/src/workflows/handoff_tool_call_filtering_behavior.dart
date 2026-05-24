/// Specifies how tool calls are filtered from handoff workflow history.
enum HandoffToolCallFilteringBehavior {
  /// Do not filter function calls or function results.
  none,

  /// Filter only handoff-related function calls and matching results.
  handoffOnly,

  /// Filter all function calls and matching results.
  all,
}
