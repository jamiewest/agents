import 'dart:math';

import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import 'compaction_message_index.dart';
import 'compaction_log_messages.dart';
import 'compaction_telemetry.dart';
import 'compaction_trigger.dart';

/// Base class for strategies that compact a [CompactionMessageIndex].
abstract class CompactionStrategy {
  CompactionStrategy(this.trigger, {CompactionTrigger? target})
    : target = target ?? ((index) => !trigger(index));

  final CompactionTrigger trigger;
  final CompactionTrigger target;

  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  );

  Future<bool> compact(
    CompactionMessageIndex index, {
    Logger? logger,
    CancellationToken? cancellationToken,
  }) async {
    final strategyName = runtimeType.toString();
    logger ??= NullLogger.instance;
    final activity = CompactionTelemetry.activitySource.startActivity(
      CompactionTelemetry.activityNames.compact,
    );
    activity?.setTag(CompactionTelemetry.tags.strategy, strategyName);

    if (index.includedNonSystemGroupCount <= 1 || !trigger(index)) {
      activity?.setTag(CompactionTelemetry.tags.triggered, false);
      logger.logCompactionSkipped(strategyName);
      return false;
    }

    activity?.setTag(CompactionTelemetry.tags.triggered, true);
    final beforeTokens = index.includedTokenCount;
    final beforeGroups = index.includedGroupCount;
    final beforeMessages = index.includedMessageCount;
    final stopwatch = Stopwatch()..start();
    final compacted = await compactCore(
      index,
      logger,
      cancellationToken ?? CancellationToken.none,
    );
    stopwatch.stop();

    activity?.setTag(CompactionTelemetry.tags.compacted, compacted);
    if (compacted) {
      activity
        ?..setTag(CompactionTelemetry.tags.beforeTokens, beforeTokens)
        ..setTag(CompactionTelemetry.tags.afterTokens, index.includedTokenCount)
        ..setTag(CompactionTelemetry.tags.beforeMessages, beforeMessages)
        ..setTag(
          CompactionTelemetry.tags.afterMessages,
          index.includedMessageCount,
        )
        ..setTag(CompactionTelemetry.tags.beforeGroups, beforeGroups)
        ..setTag(CompactionTelemetry.tags.afterGroups, index.includedGroupCount)
        ..setTag(
          CompactionTelemetry.tags.durationMs,
          stopwatch.elapsedMilliseconds,
        );
      logger.logCompactionCompleted(
        strategyName,
        stopwatch.elapsedMilliseconds,
        beforeMessages,
        index.includedMessageCount,
        beforeGroups,
        index.includedGroupCount,
        beforeTokens,
        index.includedTokenCount,
      );
    }

    return compacted;
  }

  static int ensureNonNegative(int? value) => max(0, value ?? 0);
}
