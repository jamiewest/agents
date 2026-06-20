import 'package:extensions/system.dart';

import 'loop_context.dart';
import 'loop_evaluation.dart';
import 'loop_evaluator.dart';

/// A callback that decides whether to re-invoke the agent and what feedback to
/// provide, given the full [LoopContext].
typedef LoopEvaluateCallback =
    Future<LoopEvaluation> Function(
      LoopContext context, {
      CancellationToken? cancellationToken,
    });

/// A [LoopEvaluator] that delegates the re-invocation decision and feedback to a
/// user-supplied callback.
///
/// This is the most flexible evaluator: the supplied delegate receives the full
/// [LoopContext] and returns a [LoopEvaluation], so it can decide both whether
/// to continue and what feedback (if any) to provide.
class DelegateLoopEvaluator extends LoopEvaluator {
  /// Creates a [DelegateLoopEvaluator] backed by [evaluate].
  DelegateLoopEvaluator(this._evaluate);

  final LoopEvaluateCallback _evaluate;

  @override
  Future<LoopEvaluation> evaluate(
    LoopContext context, {
    CancellationToken? cancellationToken,
  }) => _evaluate(context, cancellationToken: cancellationToken);
}
