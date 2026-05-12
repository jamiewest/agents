import 'eval_item.dart';
import 'check_result.dart';

/// Function for a synchronous evaluation check on a single [item].
///
/// Returns the check result.
typedef EvalCheck = EvalCheckResult Function(EvalItem item);
