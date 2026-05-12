import '../../func_typedefs.dart';
import 'check_result.dart';
import 'eval_check.dart';

/// Factory for creating [EvalCheck] delegates from typed lambda functions.
class FunctionEvaluator {
  FunctionEvaluator._();

  /// Creates a check from a function that takes response text and returns a
  /// bool.
  static EvalCheck create(String name, {required Func<String, bool> check}) {
    return (item) {
      final passed = check(item.response);
      return EvalCheckResult(passed, passed ? 'Passed' : 'Failed', name);
    };
  }
}
