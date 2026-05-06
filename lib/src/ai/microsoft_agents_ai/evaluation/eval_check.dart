import 'eval_item.dart';
import 'check_result.dart';

/// Function for a synchronous evaluation check on a single item.
///
/// Returns: The check result.
///
/// [item] The evaluation item.
typedef EvalCheck = EvalCheckResult Function(EvalItem item);
