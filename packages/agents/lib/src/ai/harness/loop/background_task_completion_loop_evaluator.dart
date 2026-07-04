import 'package:extensions/system.dart';

import '../background_agents/background_agents_provider.dart';
import '../background_agents/background_task_info.dart';
import 'background_task_completion_loop_evaluator_options.dart';
import 'loop_context.dart';
import 'loop_evaluation.dart';
import 'loop_evaluator.dart';

/// A [LoopEvaluator] that keeps re-invoking the wrapped agent until a
/// [BackgroundAgentsProvider] reports that no background tasks are still
/// running.
///
/// The required [BackgroundAgentsProvider] is not supplied directly. It is
/// resolved at evaluation time from the looped agent via
/// `AIAgent.getService`. This works because an agent surfaces its registered
/// `AIContextProvider` instances through `getService`, so a single
/// [BackgroundAgentsProvider] attached to the agent's session is discovered
/// automatically.
///
/// Only tasks that are still running are treated as incomplete; completed,
/// failed, and lost tasks are terminal and do not keep the loop going. While
/// running tasks remain, the evaluator continues with feedback built from a
/// template (see
/// [BackgroundTaskCompletionLoopEvaluatorOptions.feedbackMessageTemplate]),
/// with the running task list substituted for [incompleteTasksPlaceholder]
/// and the running task count substituted for
/// [incompleteTaskCountPlaceholder]. How that feedback is delivered to the
/// agent (and whether the session is reset) is decided by the `LoopAgent`
/// that consumes this evaluator.
class BackgroundTaskCompletionLoopEvaluator extends LoopEvaluator {
  /// Creates the evaluator, optionally configured by [options].
  BackgroundTaskCompletionLoopEvaluator({
    BackgroundTaskCompletionLoopEvaluatorOptions? options,
  }) : _feedbackMessageTemplate =
           options?.feedbackMessageTemplate ?? defaultFeedbackMessageTemplate;

  /// The placeholder token that is replaced, on each evaluation, with a
  /// formatted list of the background tasks that are still running.
  static const String incompleteTasksPlaceholder = '{incomplete_tasks}';

  /// The placeholder token that is replaced, on each evaluation, with the
  /// number of background tasks that are still running.
  static const String incompleteTaskCountPlaceholder =
      '{incomplete_task_count}';

  /// The default template used to build the feedback produced while
  /// background tasks are still running.
  static const String defaultFeedbackMessageTemplate =
      'You still have $incompleteTaskCountPlaceholder background task(s) '
      'running that must finish before you can complete the work:\n'
      '$incompleteTasksPlaceholder\n\n'
      'Wait for these tasks to complete, retrieve their results, and '
      'incorporate them. Only stop once every background task has finished.';

  final String _feedbackMessageTemplate;

  @override
  Future<LoopEvaluation> evaluate(
    LoopContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final provider =
        context.agent.getService(BackgroundAgentsProvider)
            as BackgroundAgentsProvider?;
    if (provider == null) {
      throw StateError(
        'BackgroundTaskCompletionLoopEvaluator requires a '
        'BackgroundAgentsProvider to be registered on the agent, but none '
        'could be resolved via getService.',
      );
    }

    final incomplete = provider.getIncompleteTasks(context.session);
    if (incomplete.isEmpty) {
      return LoopEvaluation.stop();
    }

    final feedback = _feedbackMessageTemplate
        .replaceAll(incompleteTaskCountPlaceholder, '${incomplete.length}')
        .replaceAll(incompleteTasksPlaceholder, _formatTasks(incomplete));
    return LoopEvaluation.proceed(feedback);
  }

  static String _formatTasks(List<BackgroundTaskInfo> incomplete) => [
    for (final task in incomplete)
      '- #${task.id} (${task.agentName}): ${task.description}',
  ].join('\n');
}
