import 'dart:math';
import 'package:extensions/system.dart';
import 'package:extensions/logging.dart';
import 'compaction_group_kind.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';
import 'compaction_trigger.dart';
import '../../../map_extensions.dart';

/// A compaction strategy that removes the oldest user turns and their
/// associated response groups to bound conversation length.
///
/// Remarks: This strategy always preserves system messages. It identifies
/// user turns in the conversation (via [TurnIndex]) and excludes the oldest
/// turns one at a time until the [Target] condition is met.
/// [MinimumPreservedTurns] is a hard floor: even if the [Target] has not been
/// reached, compaction will not touch the last [MinimumPreservedTurns] turns
/// (by [TurnIndex]). Groups with a [TurnIndex] of `0` or `null` are always
/// preserved regardless of this setting. This strategy is more predictable
/// than token-based truncation for bounding conversation length, since it
/// operates on logical turn boundaries rather than estimated token counts.
class SlidingWindowCompactionStrategy extends CompactionStrategy {
  /// Initializes a new instance of the [SlidingWindowCompactionStrategy] class.
  ///
  /// [trigger] The [CompactionTrigger] that controls when compaction proceeds.
  /// Use [Int32)] for turn-based thresholds.
  ///
  /// [minimumPreservedTurns] The minimum number of most-recent turns (by
  /// [TurnIndex]) to preserve. This is a hard floor — compaction will not
  /// exclude turns within this range, regardless of the target condition.
  /// Groups with [TurnIndex] of `0` or `null` are always preserved.
  ///
  /// [target] An optional target condition that controls when compaction stops.
  /// When `null`, defaults to the inverse of the `trigger` — compaction stops
  /// as soon as the trigger would no longer fire.
  SlidingWindowCompactionStrategy(
    CompactionTrigger trigger,
    {int? minimumPreservedTurns = null, CompactionTrigger? target = null, },
  ) {
    this.minimumPreservedTurns = ensureNonNegative(minimumPreservedTurns);
  }

  /// Gets the minimum number of most-recent turns (by [TurnIndex]) that are
  /// always preserved. This is a hard floor that compaction cannot exceed,
  /// regardless of the target condition. Groups with [TurnIndex] of `0` or
  /// `null` are always preserved independently of this value.
  late final int minimumPreservedTurns;

  @override
  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  ) {
    var turnGroups = [];
    var turnOrder = [];
    for (var i = 0; i < index.groups.length; i++) {
      var group = index.groups[i];
      if (!group.isExcluded && group.kind != CompactionGroupKind.system && group.turnIndex is int) {
        final turnIndex = !group.isExcluded && group.kind != CompactionGroupKind.system && group.turnIndex as int;
        if (!turnGroups.tryGetValue(turnIndex)) {
          indices = [];
          turnGroups[turnIndex] = indices;
          turnOrder.add(turnIndex);
        }
        indices.add(i);
      }
    }
    var protectedTurnIndices = [];
    if (turnGroups.containsKey(0)) {
      protectedTurnIndices.add(0);
    }
    var turnsToProtect = min(this.minimumPreservedTurns, turnOrder.length);
    for (var i = turnOrder.length - turnsToProtect; i < turnOrder.length; i++) {
      protectedTurnIndices.add(turnOrder[i]);
    }
    var compacted = false;
    for (var t = 0; t < turnOrder.length; t++) {
      var currentTurnIndex = turnOrder[t];
      if (protectedTurnIndices.contains(currentTurnIndex)) {
        continue;
      }
      var groupIndices = turnGroups[currentTurnIndex];
      for (var g = 0; g < groupIndices.length; g++) {
        var idx = groupIndices[g];
        index.groups[idx].isExcluded = true;
        index.groups[idx].excludeReason = 'Excluded by ${'SlidingWindowCompactionStrategy'}';
      }
      compacted = true;
      if (this.target(index)) {
        break;
      }
    }
    return Future<bool>(compacted);
  }
}
