/// Configuration options for a todo-completion loop evaluator.
class TodoCompletionLoopEvaluatorOptions {
  /// The set of mode names for which the evaluator drives re-invocation, or
  /// `null` to apply in every mode.
  ///
  /// When `null`, the evaluator applies in every mode and no mode provider is
  /// required. When non-`null` it must contain at least one non-empty mode name,
  /// and a mode provider must be resolvable from the agent at evaluation time.
  Iterable<String>? modes;

  /// The template used to build the feedback produced while incomplete todo
  /// items remain, or `null` to use the evaluator's default.
  ///
  /// Any occurrence of the remaining-todos placeholder is replaced, on each
  /// evaluation, with a formatted list of the remaining (incomplete) items.
  String? feedbackMessageTemplate;
}
