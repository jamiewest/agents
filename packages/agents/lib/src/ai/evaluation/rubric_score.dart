/// A single dimension's score from a rubric-based evaluator run.
///
/// Rubric evaluators (such as the generated rubric evaluators produced by
/// Azure AI Foundry's adaptive evals) emit one [RubricScore] per dimension
/// per item, alongside an overall weighted score. Attach instances to
/// `EvalScoreResult.dimensions` as a typed view of the per-dimension
/// breakdown returned by the provider (e.g. `properties.dimension_scores`).
///
/// Non-rubric evaluators (built-in quality, safety, or agent-behavior
/// evaluators) leave `EvalScoreResult.dimensions` as `null`.
class RubricScore {
  /// Creates a rubric dimension score.
  const RubricScore(
    this.id,
    this.score, {
    required this.applicable,
    required this.weight,
    required this.reason,
  });

  /// Dimension identifier — matches the id defined on the rubric.
  final String id;

  /// Numeric score for the dimension, or `null` when the dimension was
  /// marked non-applicable for this item. Foundry rubric evaluators emit
  /// integer scores on a 1–5 scale.
  final int? score;

  /// Whether the dimension applied to this item.
  final bool applicable;

  /// Dimension weight, mirroring the rubric definition.
  final int weight;

  /// Short rationale produced by the evaluator.
  final String reason;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RubricScore &&
        id == other.id &&
        score == other.score &&
        applicable == other.applicable &&
        weight == other.weight &&
        reason == other.reason;
  }

  @override
  int get hashCode => Object.hash(id, score, applicable, weight, reason);
}
