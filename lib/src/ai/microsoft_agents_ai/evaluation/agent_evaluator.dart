import 'package:extensions/system.dart';
import 'agent_evaluation_results.dart';
import 'eval_item.dart';

/// Batch-oriented evaluator interface for agent evaluation.
///
/// Remarks: Unlike MEAI's `IEvaluator` which evaluates one item at a time,
/// [AgentEvaluator] evaluates a batch of items. This enables efficient
/// cloud-based evaluation (e.g., Foundry) and aggregate result computation.
abstract class AgentEvaluator {
  /// Gets the evaluator name.
  String get name;

  /// Evaluates a batch of items and returns aggregate results.
  ///
  /// Returns: Aggregate evaluation results.
  ///
  /// [items] The items to evaluate.
  ///
  /// [evalName] A display name for this evaluation run.
  ///
  /// [cancellationToken] Cancellation token.
  Future<AgentEvaluationResults> evaluate(
    List<EvalItem> items, {
    String? evalName,
    CancellationToken? cancellationToken,
  });
}
