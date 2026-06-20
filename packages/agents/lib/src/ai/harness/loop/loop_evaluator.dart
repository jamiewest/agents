import 'package:extensions/system.dart';

import 'loop_context.dart';
import 'loop_evaluation.dart';

/// The abstract base class for the component that decides, after each agent
/// iteration, whether a loop agent should re-invoke the wrapped agent and what
/// feedback to provide.
///
/// A [LoopEvaluator] is pure judgment: it inspects the [LoopContext] and returns
/// a [LoopEvaluation] describing whether to continue and any feedback for the
/// next iteration. It does not manage the session or construct the next input
/// messages — that is the responsibility of the loop agent that consumes it.
///
/// Implementations should be stateless and safe to share across concurrent loop
/// runs; any per-run state must be stored on the supplied [LoopContext].
abstract class LoopEvaluator {
  /// Evaluates the loop state after an iteration and decides whether to
  /// re-invoke the wrapped agent and what feedback to provide.
  Future<LoopEvaluation> evaluate(
    LoopContext context, {
    CancellationToken? cancellationToken,
  });
}
