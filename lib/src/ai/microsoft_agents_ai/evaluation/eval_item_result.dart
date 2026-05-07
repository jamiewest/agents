/// Per-item result from a Foundry evaluation run, with individual evaluator
/// scores and error details.
class EvalItemResult {
  EvalItemResult(this.itemId, this.status, List<EvalScoreResult> scores)
    : scores = List<EvalScoreResult>.of(scores);

  /// Gets the output item ID from the evaluation API.
  final String itemId;

  /// Gets the item evaluation status.
  final String status;

  /// Gets the per-evaluator score results.
  final List<EvalScoreResult> scores;

  String? errorCode;
  String? errorMessage;
  String? responseId;
  String? inputText;
  String? outputText;
  Map<String, int>? tokenUsage;

  /// Gets whether this item is in an error state.
  bool get isError => status == 'error' || status == 'errored';

  /// Gets whether this item passed all evaluators.
  bool get isPassed =>
      scores.isNotEmpty && scores.every((s) => s.passed == true);

  /// Gets whether this item failed any evaluator.
  bool get isFailed => scores.any((s) => s.passed == false);
}

/// A single evaluator's score on one evaluation item.
class EvalScoreResult {
  EvalScoreResult(this.name, this.score, {this.passed});

  String name;
  double score;
  bool? passed;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EvalScoreResult &&
        name == other.name &&
        score == other.score &&
        passed == other.passed;
  }

  @override
  int get hashCode => Object.hash(name, score, passed);
}

/// Per-evaluator pass/fail breakdown from an evaluation run.
class PerEvaluatorResult {
  const PerEvaluatorResult(this.passed, this.failed);

  final int passed;
  final int failed;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PerEvaluatorResult &&
        passed == other.passed &&
        failed == other.failed;
  }

  @override
  int get hashCode => Object.hash(passed, failed);
}
