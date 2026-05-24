import 'dart:math';

import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import 'compaction_group_kind.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';

/// A compaction strategy that removes the oldest user turns and their
/// associated response groups to bound conversation length.
class SlidingWindowCompactionStrategy extends CompactionStrategy {
  SlidingWindowCompactionStrategy(
    super.trigger, {
    int? minimumPreservedTurns,
    super.target,
  }) {
    this.minimumPreservedTurns = CompactionStrategy.ensureNonNegative(
      minimumPreservedTurns,
    );
  }

  late final int minimumPreservedTurns;

  @override
  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  ) async {
    final turnGroups = <int, List<int>>{};
    final turnOrder = <int>[];

    for (var i = 0; i < index.groups.length; i++) {
      final group = index.groups[i];
      final turnIndex = group.turnIndex;
      if (group.isExcluded ||
          group.kind == CompactionGroupKind.system ||
          turnIndex == null) {
        continue;
      }

      final indices = turnGroups.putIfAbsent(turnIndex, () {
        turnOrder.add(turnIndex);
        return <int>[];
      });
      indices.add(i);
    }

    final protectedTurnIndices = <int>{};
    if (turnGroups.containsKey(0)) {
      protectedTurnIndices.add(0);
    }

    final turnsToProtect = min(minimumPreservedTurns, turnOrder.length);
    for (var i = turnOrder.length - turnsToProtect; i < turnOrder.length; i++) {
      protectedTurnIndices.add(turnOrder[i]);
    }

    var compacted = false;
    for (final currentTurnIndex in turnOrder) {
      if (protectedTurnIndices.contains(currentTurnIndex)) {
        continue;
      }

      for (final groupIndex in turnGroups[currentTurnIndex]!) {
        final group = index.groups[groupIndex];
        group.isExcluded = true;
        group.excludeReason = 'Excluded by SlidingWindowCompactionStrategy';
      }

      compacted = true;
      if (target(index)) {
        break;
      }
    }

    return compacted;
  }
}
