import 'dart:math';
import 'package:extensions/system.dart';
import 'package:extensions/logging.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/chat_history_provider.dart';
import 'compaction_message_index.dart';
import 'compaction_telemetry.dart';
import 'compaction_trigger.dart';
import 'pipeline_compaction_strategy.dart';

/// Base class for strategies that compact a [CompactionMessageIndex] to
/// reduce context size.
///
/// Remarks: Compaction strategies operate on [CompactionMessageIndex]
/// instances, which organize messages into atomic groups that respect the
/// tool-call/result pairing constraint. Strategies mutate the collection in
/// place by marking groups as excluded, removing groups, or replacing message
/// content (e.g., with summaries). Every strategy requires a
/// [CompactionTrigger] that determines whether compaction should proceed
/// based on current [CompactionMessageIndex] metrics (token count, message
/// count, turn count, etc.). The base class evaluates this trigger at the
/// start of [CancellationToken)] and skips compaction when the trigger
/// returns `false`. An optional target condition controls when compaction
/// stops. Strategies incrementally exclude groups and re-evaluate the target
/// after each exclusion, stopping as soon as the target returns `true`. When
/// no target is specified, it defaults to the inverse of the trigger —
/// meaning compaction stops when the trigger condition would no longer fire.
/// Strategies can be applied at three lifecycle points: In-run : During the
/// tool loop, before each LLM call, to keep context within token limits.
/// Pre-write : Before persisting messages to storage via
/// [ChatHistoryProvider]. On existing storage : As a maintenance operation to
/// compact stored history. Multiple strategies can be composed by applying
/// them sequentially to the same [CompactionMessageIndex] via
/// [PipelineCompactionStrategy].
abstract class CompactionStrategy {
  /// Initializes a new instance of the [CompactionStrategy] class.
  ///
  /// [trigger] The [CompactionTrigger] that determines whether compaction
  /// should proceed.
  ///
  /// [target] An optional target condition that controls when compaction stops.
  /// Strategies re-evaluate this predicate after each incremental exclusion and
  /// stop when it returns `true`. When `null`, defaults to the inverse of the
  /// `trigger` — compaction stops as soon as the trigger condition would no
  /// longer fire.
  CompactionStrategy(
    this.trigger,
    {CompactionTrigger? target, }
  ) {
    this.target = target ?? ((index) => !trigger(index));
  }

  /// Gets the trigger predicate that controls when compaction proceeds.
  final CompactionTrigger trigger;

  /// Gets the target predicate that controls when compaction stops. Strategies
  /// re-evaluate this after each incremental exclusion and stop when it returns
  /// `true`.
  late final CompactionTrigger target;

  /// Applies the strategy-specific compaction logic to the specified message
  /// index.
  ///
  /// Remarks: This method is called by [CancellationToken)] only when the
  /// [Trigger] returns `true`. Implementations do not need to evaluate the
  /// trigger or report metrics — the base class handles both. Implementations
  /// should use [Target] to determine when to stop compacting incrementally.
  ///
  /// Returns: A task whose result is `true` if any compaction was performed,
  /// `false` otherwise.
  ///
  /// [index] The message index to compact. The strategy mutates this collection
  /// in place.
  ///
  /// [logger] The [Logger] for emitting compaction diagnostics.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests.
  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  );
  /// Evaluates the [Trigger] and, when it fires, delegates to
  /// [CancellationToken)] and reports compaction metrics.
  ///
  /// Returns: A task representing the asynchronous operation. The task result
  /// is `true` if compaction occurred, `false` otherwise.
  ///
  /// [index] The message index to compact. The strategy mutates this collection
  /// in place.
  ///
  /// [logger] An optional [Logger] for emitting compaction diagnostics. When
  /// `null`, logging is disabled.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests.
  Future<bool> compact(
    CompactionMessageIndex index,
    {Logger? logger, CancellationToken? cancellationToken, }
  ) async {
    var strategyName = this.runtimeType.toString();
    logger ??= NullLogger.instance;
    var activity = CompactionTelemetry.activitySource.startActivity(CompactionTelemetry.activityNames.compact);
    activity?.setTag(CompactionTelemetry.tags.strategy, strategyName);
    if (index.includedNonSystemGroupCount <= 1 || !this.trigger(index)) {
      activity?.setTag(CompactionTelemetry.tags.triggered, false);
      logger.logCompactionSkipped(strategyName);
      return false;
    }
    activity?.setTag(CompactionTelemetry.tags.triggered, true);
    var beforeTokens = index.includedTokenCount;
    var beforeGroups = index.includedGroupCount;
    var beforeMessages = index.includedMessageCount;
    var stopwatch = (Stopwatch()..start());
    var compacted = await this.compactCoreAsync(
      index,
      logger,
      cancellationToken,
    ) ;
    stopwatch.stop();
    activity?.setTag(CompactionTelemetry.tags.compacted, compacted);
    if (compacted) {
      activity?
                .setTag(CompactionTelemetry.tags.beforeTokens, beforeTokens)
                .setTag(CompactionTelemetry.tags.afterTokens, index.includedTokenCount)
                .setTag(CompactionTelemetry.tags.beforeMessages, beforeMessages)
                .setTag(CompactionTelemetry.tags.afterMessages, index.includedMessageCount)
                .setTag(CompactionTelemetry.tags.beforeGroups, beforeGroups)
                .setTag(CompactionTelemetry.tags.afterGroups, index.includedGroupCount)
                .setTag(CompactionTelemetry.tags.durationMs, stopwatch.elapsedMilliseconds);
      logger.logCompactionCompleted(
                strategyName,
                stopwatch.elapsedMilliseconds,
                beforeMessages,
                index.includedMessageCount,
                beforeGroups,
                index.includedGroupCount,
                beforeTokens,
                index.includedTokenCount);
    }
    return compacted;
  }

  /// Ensures the provided value is not a negative number.
  ///
  /// Returns: 0 if negative; otherwise the value
  ///
  /// [value] The target value.
  static int ensureNonNegative(int value) {
    return max(0, value);
  }
}
