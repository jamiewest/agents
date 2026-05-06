/// Per-item result from a Foundry evaluation run, with individual evaluator
/// scores and error details.
class EvalItemResult {
  /// Initializes a new instance of the [EvalItemResult] class.
  ///
  /// [itemId] The output item ID from the evaluation API.
  ///
  /// [status] The item evaluation status (e.g., "pass", "fail", "error").
  ///
  /// [scores] Per-evaluator score results.
  EvalItemResult(
    String itemId,
    String status,
    List<EvalScoreResult> scores,
  ) :
      itemId = itemId,
      status = status,
      scores = scores {
  }

  /// Gets the output item ID from the evaluation API.
  final String itemId;

  /// Gets the item evaluation status (e.g., "pass", "fail", "error",
  /// "errored").
  final String status;

  /// Gets the per-evaluator score results.
  final List<EvalScoreResult> scores;

  /// Gets or sets an error code when the item evaluation errored.
  String? errorCode;

  /// Gets or sets an error message when the item evaluation errored.
  String? errorMessage;

  /// Gets or sets the response ID from the evaluation API (e.g., for
  /// response-based evals).
  String? responseId;

  /// Gets or sets the input text echoed back by the evaluation API.
  String? inputText;

  /// Gets or sets the output text echoed back by the evaluation API.
  String? outputText;

  /// Gets or sets token usage information from the evaluation.
  Map<String, int>? tokenUsage;

  /// Gets whether this item is in an error state.
  bool get isError {
    return status == "error" || status == "errored";
  }

  /// Gets whether this item passed all evaluators.
  bool get isPassed {
    return this.scores.length > 0 && this.scores.every((s) => s.passed == true);
  }

  /// Gets whether this item failed any evaluator.
  bool get isFailed {
    return this.scores.any((s) => s.passed == false);
  }
}
/// A single evaluator's score on one evaluation item.
///
/// [Name] The evaluator name that produced this score.
///
/// [Score] The numeric score value.
///
/// [Passed] Whether the evaluator considered this a pass, or null if not
/// determined.
class EvalScoreResult {
  /// A single evaluator's score on one evaluation item.
  ///
  /// [Name] The evaluator name that produced this score.
  ///
  /// [Score] The numeric score value.
  ///
  /// [Passed] Whether the evaluator considered this a pass, or null if not
  /// determined.
  EvalScoreResult(String Name, double Score, {bool? Passed = null, }) : name = Name, score = Score;

  /// The evaluator name that produced this score.
  String name;

  /// The numeric score value.
  double score;

  /// Whether the evaluator considered this a pass, or null if not determined.
  bool? passed;

  @override
  bool operator ==(Object other) { if (identical(this, other)) return true;
    return other is EvalScoreResult &&
    name == other.name &&
    score == other.score &&
    passed == other.passed; }
  @override
  int get hashCode { return Object.hash(name, score, passed); }
}
/// Per-evaluator pass/fail breakdown from an evaluation run.
///
/// [Passed] Number of items that passed for this evaluator.
///
/// [Failed] Number of items that failed for this evaluator.
class PerEvaluatorResult {
  /// Per-evaluator pass/fail breakdown from an evaluation run.
  ///
  /// [Passed] Number of items that passed for this evaluator.
  ///
  /// [Failed] Number of items that failed for this evaluator.
  const PerEvaluatorResult(int Passed, int Failed, ) : passed = Passed, failed = Failed;

  /// Number of items that passed for this evaluator.
  final int passed;

  /// Number of items that failed for this evaluator.
  final int failed;

  @override
  bool operator ==(Object other) { if (identical(this, other)) return true;
    return other is PerEvaluatorResult &&
    passed == other.passed &&
    failed == other.failed; }
  @override
  int get hashCode { return Object.hash(passed, failed); }
}
