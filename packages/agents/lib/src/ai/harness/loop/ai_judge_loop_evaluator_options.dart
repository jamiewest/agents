/// Configuration options for an AI-judge loop evaluator.
class AIJudgeLoopEvaluatorOptions {
  /// The system instructions used to prompt the judge, or `null` to use the
  /// evaluator's default.
  ///
  /// Any occurrence of the criteria placeholder is replaced with the rendered
  /// [criteria] (or removed when no criteria are supplied).
  String? instructions;

  /// An optional list of additional criteria the agent's response must satisfy,
  /// evaluated by the judge alongside the original request.
  ///
  /// When supplied, the criteria are rendered into the judge instructions
  /// wherever the criteria placeholder appears. When `null` or empty, the
  /// placeholder is removed and no criteria are added.
  Iterable<String>? criteria;

  /// The template used to build the feedback produced when the judge decides the
  /// original request was not fully addressed, or `null` to use the evaluator's
  /// default.
  ///
  /// Any occurrence of the gap-analysis placeholder is replaced with the judge's
  /// gap analysis (or a placeholder when none is available).
  String? feedbackMessageTemplate;
}
