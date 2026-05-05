import 'eval_item.dart';
import 'eval_item_result.dart';

/// Aggregate evaluation results across multiple items.
class AgentEvaluationResults {
  /// Initializes a new instance of the [AgentEvaluationResults] class.
  ///
  /// [providerName] Name of the evaluation provider.
  ///
  /// [items] Per-item MEAI evaluation results.
  ///
  /// [inputItems] The original eval items that were evaluated, for auditing.
  AgentEvaluationResults(
    String providerName,
    Iterable<EvaluationResult> items,
    {List<EvalItem>? inputItems = null, },
  ) :
      providerName = providerName,
      items = items {
    this._items = List<EvaluationResult>(items);
    this.inputItems = inputItems;
  }

  late final List<EvaluationResult> _items;

  /// Gets the evaluation provider name.
  final String providerName;

  /// Gets the portal URL for viewing results (Foundry only).
  Uri? reportUrl;

  /// Gets the Foundry evaluation ID (Foundry only).
  String? evalId;

  /// Gets the Foundry evaluation run ID (Foundry only).
  String? runId;

  /// Gets the evaluation run status (e.g., "completed", "failed", "canceled",
  /// "timeout").
  String? status;

  /// Gets error details when the evaluation run failed.
  String? error;

  /// Gets the original eval items that produced these results, for auditing.
  /// Each entry corresponds positionally to [Items] — `InputItems[i]` is the
  /// query/response that produced `Items[i]`.
  late final List<EvalItem>? inputItems;

  /// Gets per-agent results for workflow evaluations.
  Map<String, AgentEvaluationResults>? subResults;

  /// Gets per-evaluator pass/fail breakdown (Foundry only).
  Map<String, PerEvaluatorResult>? perEvaluator;

  /// Gets detailed per-item results from the Foundry output_items API,
  /// including individual evaluator scores, error info, and token usage.
  List<EvalItemResult>? detailedItems;

  /// Gets whether all items passed.
  final bool allPassed;

  /// Gets the per-item MEAI evaluation results.
  List<EvaluationResult> get items {
    return this._items;
  }

  /// Gets the number of items that passed.
  int get passed {
    return this._items.length(ItemPassed);
  }

  /// Gets the number of items that failed.
  int get failed {
    return this._items.length((i) => !itemPassed(i));
  }

  /// Gets the total number of items evaluated.
  int get total {
    return this._items.length;
  }

  /// Asserts that all items passed. Throws [InvalidOperationException] on
  /// failure.
  ///
  /// [message] Optional custom failure message.
  void assertAllPassed({String? message}) {
    if (!this.allPassed) {
      var detail = message ?? '${this.providerName}: ${this.passed} passed, ${this.failed} failed of ${this.total}.';
      if (this.reportUrl != null) {
        detail += ' See ${this.reportUrl} for details.';
      }
      if (this.subResults != null) {
        var failedAgents = this.subResults
                    .where((kvp) => !kvp.value.allPassed)
                    .map((kvp) => kvp.key);
        detail += ' failed agents: ${failedAgents.join(", ")}.';
      }
      throw StateError(detail);
    }
  }

  static bool itemPassed(EvaluationResult result) {
    for (final metric in result.metrics.values) {
      if (metric.interpretation?.failed == true) {
        return false;
      }
      if (metric is BooleanMetric boolean && boolean.value == false) {
        return false;
      }
    }
    return result.metrics.length > 0;
  }
}
