import 'package:extensions/system.dart';
import 'agent_evaluation_results.dart';
import 'agent_evaluator.dart';
import 'check_result.dart';
import 'eval_check.dart';
import 'eval_item.dart';

/// Evaluator that runs check functions locally without API calls.
class LocalEvaluator implements AgentEvaluator {
  /// Initializes a new instance of the [LocalEvaluator] class.
  ///
  /// [checks] The check functions to run on each item.
  LocalEvaluator(List<EvalCheck> checks) : _checks = checks {
  }

  final List<EvalCheck> _checks;

  String get name {
    return "LocalEvaluator";
  }

  @override
  Future<AgentEvaluationResults> evaluate(
    List<EvalItem> items,
    {String? evalName, CancellationToken? cancellationToken, }
  ) {
    var results = List<EvaluationResult>(items.length);
    for (final item in items) {
      cancellationToken.throwIfCancellationRequested();
      var evalResult = evaluationResult();
      for (final check in this._checks) {
        var EvalCheckResult = check(item);
        evalResult.metrics[EvalCheckResult.checkName] = booleanMetric(
                    EvalCheckResult.checkName,
                    EvalCheckResult.passed,
                    reason: EvalCheckResult.reason),
                };
    }
    results.add(evalResult);
  }

  return Future.value(agentEvaluationResults(this.name, results, inputItems: items));
}
 }
