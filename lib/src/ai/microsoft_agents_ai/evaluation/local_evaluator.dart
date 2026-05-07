import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'agent_evaluation_results.dart';
import 'agent_evaluator.dart';
import 'eval_check.dart';
import 'eval_item.dart';

/// Evaluator that runs check functions locally without API calls.
class LocalEvaluator implements AgentEvaluator {
  LocalEvaluator(List<EvalCheck> checks) : _checks = List<EvalCheck>.of(checks);

  final List<EvalCheck> _checks;

  @override
  String get name => 'LocalEvaluator';

  @override
  Future<AgentEvaluationResults> evaluate(
    List<EvalItem> items, {
    String? evalName,
    CancellationToken? cancellationToken,
  }) async {
    final results = <EvaluationResult>[];
    for (final item in items) {
      cancellationToken?.throwIfCancellationRequested();
      final evalResult = EvaluationResult();
      for (final check in _checks) {
        final checkResult = check(item);
        evalResult.metrics[checkResult.checkName] = BooleanMetric(
          checkResult.checkName,
          value: checkResult.passed,
          reason: checkResult.reason,
        );
      }
      results.add(evalResult);
    }

    return AgentEvaluationResults(name, results, inputItems: items);
  }
}
