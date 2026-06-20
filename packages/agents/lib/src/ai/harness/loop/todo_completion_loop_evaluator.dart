import 'package:extensions/system.dart';

import '../agent_mode/agent_mode_provider.dart';
import '../todo/todo_item.dart';
import '../todo/todo_provider.dart';
import 'loop_context.dart';
import 'loop_evaluation.dart';
import 'loop_evaluator.dart';
import 'todo_completion_loop_evaluator_options.dart';

/// A [LoopEvaluator] that keeps re-invoking the wrapped agent until a
/// [TodoProvider] has no remaining (incomplete) todo items, optionally only
/// while the agent is operating in one of a configured set of modes tracked by
/// an [AgentModeProvider].
///
/// The required [TodoProvider] — and, when modes are configured, the
/// [AgentModeProvider] — are resolved at evaluation time from the looped agent
/// via `getServiceOf`, so the evaluator can be added to a harness agent's loop
/// without additional wiring.
class TodoCompletionLoopEvaluator extends LoopEvaluator {
  /// The placeholder token replaced, on each evaluation, with a formatted list
  /// of the remaining (incomplete) todo items.
  static const String remainingTodosPlaceholder = '{remaining_todos}';

  /// The default template used to build the feedback produced while incomplete
  /// todo items remain.
  static const String defaultFeedbackMessageTemplate =
      'You still have incomplete todo items. Continue working until every '
      'item is complete, marking each item as complete when finished. The '
      'following items are still open:\n$remainingTodosPlaceholder';

  /// Creates a [TodoCompletionLoopEvaluator].
  ///
  /// Throws [ArgumentError] if [TodoCompletionLoopEvaluatorOptions.modes] is
  /// non-`null` but empty, or contains an empty or whitespace mode name.
  TodoCompletionLoopEvaluator({TodoCompletionLoopEvaluatorOptions? options})
    : _modes = _validateModes(options?.modes),
      _feedbackMessageTemplate =
          options?.feedbackMessageTemplate ?? defaultFeedbackMessageTemplate;

  final Set<String>? _modes;
  final String _feedbackMessageTemplate;

  @override
  Future<LoopEvaluation> evaluate(
    LoopContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final todoProvider = context.agent.getServiceOf<TodoProvider>();
    if (todoProvider == null) {
      throw StateError(
        'TodoCompletionLoopEvaluator requires a TodoProvider to be registered '
        'on the agent, but none could be resolved via getService.',
      );
    }

    final modes = _modes;
    if (modes != null) {
      final modeProvider = context.agent.getServiceOf<AgentModeProvider>();
      if (modeProvider == null) {
        throw StateError(
          'TodoCompletionLoopEvaluator was configured with modes but no '
          'AgentModeProvider could be resolved from the agent via getService.',
        );
      }
      final currentMode = modeProvider.getMode(context.session);
      if (!modes.contains(currentMode)) {
        return LoopEvaluation.stop();
      }
    }

    final remaining = await todoProvider.getRemainingTodos(context.session);
    if (remaining.isEmpty) {
      return LoopEvaluation.stop();
    }

    final feedback = _feedbackMessageTemplate.replaceAll(
      remainingTodosPlaceholder,
      _formatRemainingTodos(remaining),
    );
    return LoopEvaluation.proceed(feedback);
  }

  static Set<String>? _validateModes(Iterable<String>? modes) {
    if (modes == null) {
      return null;
    }
    final modeSet = <String>{};
    for (final mode in modes) {
      if (mode.trim().isEmpty) {
        throw ArgumentError.value(
          modes,
          'options',
          'Mode names must not be empty or whitespace.',
        );
      }
      modeSet.add(mode);
    }
    if (modeSet.isEmpty) {
      throw ArgumentError.value(
        modes,
        'options',
        'At least one mode must be supplied when modes are specified. Leave '
            'modes null to apply in every mode.',
      );
    }
    return modeSet;
  }

  static String _formatRemainingTodos(List<TodoItem> remaining) {
    final buffer = StringBuffer();
    for (var i = 0; i < remaining.length; i++) {
      final item = remaining[i];
      buffer
        ..write('- ')
        ..write(item.id)
        ..write(': ')
        ..write(item.title);
      final description = item.description;
      if (description != null && description.trim().isNotEmpty) {
        buffer
          ..write(' — ')
          ..write(description);
      }
      if (i < remaining.length - 1) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }
}
