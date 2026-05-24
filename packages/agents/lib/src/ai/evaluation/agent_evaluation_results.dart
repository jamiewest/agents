import 'package:extensions/ai.dart';

import 'eval_item.dart';
import 'eval_item_result.dart';

/// Aggregate evaluation results across multiple items.
class AgentEvaluationResults {
  AgentEvaluationResults(
    this.providerName,
    Iterable<EvaluationResult> items, {
    this.inputItems,
  }) : _items = List<EvaluationResult>.of(items) {
    allPassed = _items.every(itemPassed);
  }

  final List<EvaluationResult> _items;

  /// Gets the evaluation provider name.
  final String providerName;

  /// Gets the portal URL for viewing results.
  Uri? reportUrl;

  /// Gets the Foundry evaluation ID.
  String? evalId;

  /// Gets the Foundry evaluation run ID.
  String? runId;

  /// Gets the evaluation run status.
  String? status;

  /// Gets error details when the evaluation run failed.
  String? error;

  /// Gets the original eval items that produced these results.
  final List<EvalItem>? inputItems;

  /// Gets per-agent results for workflow evaluations.
  Map<String, AgentEvaluationResults>? subResults;

  /// Gets per-evaluator pass/fail breakdown.
  Map<String, PerEvaluatorResult>? perEvaluator;

  /// Gets detailed per-item results.
  List<EvalItemResult>? detailedItems;

  /// Gets whether all items passed.
  late final bool allPassed;

  /// Gets the per-item MEAI evaluation results.
  List<EvaluationResult> get items => _items;

  /// Gets the number of items that passed.
  int get passed => _items.where(itemPassed).length;

  /// Gets the number of items that failed.
  int get failed => total - passed;

  /// Gets the total number of items evaluated.
  int get total => _items.length;

  /// Asserts that all items passed.
  void assertAllPassed({String? message}) {
    if (allPassed) {
      return;
    }

    var detail =
        message ?? '$providerName: $passed passed, $failed failed of $total.';
    if (reportUrl != null) {
      detail += ' See $reportUrl for details.';
    }
    final subResults = this.subResults;
    if (subResults != null) {
      final failedAgents = subResults.entries
          .where((entry) => !entry.value.allPassed)
          .map((entry) => entry.key)
          .toList();
      if (failedAgents.isNotEmpty) {
        detail += ' failed agents: ${failedAgents.join(", ")}.';
      }
    }
    throw StateError(detail);
  }

  static bool itemPassed(EvaluationResult result) {
    if (result.metrics.isEmpty) {
      return false;
    }

    for (final metric in result.metrics.values) {
      if (metric.interpretation?.failed == true) {
        return false;
      }
      if (metric is BooleanMetric && metric.value == false) {
        return false;
      }
    }
    return true;
  }
}
