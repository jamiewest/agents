import '../../../func_typedefs.dart';
import 'check_result.dart';
import 'eval_check.dart';
import 'eval_item.dart';

/// Factory for creating [EvalCheck] delegates from typed lambda functions.
class FunctionEvaluator {
  FunctionEvaluator();

  /// Creates a check from a function that takes the response text and returns a
  /// bool.
  ///
  /// [name] Check name for reporting.
  ///
  /// [check] Function that returns true if the response passes.
  static EvalCheck create(String name, {Func<String, bool>? check, }) {
    return (EvalItem item) {
        
            var passed = check(item.response);
            return evalCheckResult(passed, passed ? "Passed" : "Failed", name);
        };
  }
}
