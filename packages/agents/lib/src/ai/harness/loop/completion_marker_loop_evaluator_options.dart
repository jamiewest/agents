/// Configuration options for a completion-marker loop evaluator.
class CompletionMarkerLoopEvaluatorOptions {
  /// The template used to build the feedback produced when the completion
  /// marker has not yet appeared, or `null` to use the evaluator's default.
  ///
  /// Any occurrence of the completion-marker placeholder is replaced with the
  /// configured marker. Any occurrence of the last-response placeholder is
  /// replaced, on each evaluation, with the text of the agent's latest response.
  String? feedbackMessageTemplate;
}
