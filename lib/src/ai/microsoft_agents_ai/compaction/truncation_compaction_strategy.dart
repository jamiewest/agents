import 'package:extensions/system.dart';
import 'package:extensions/logging.dart';
import 'compaction_group_kind.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';
import 'compaction_trigger.dart';

/// A compaction strategy that removes the oldest non-system message groups,
/// keeping at least [MinimumPreservedGroups] most-recent groups intact.
///
/// Remarks: This strategy preserves system messages and removes the oldest
/// non-system message groups first. It respects atomic group boundaries — an
/// assistant message with tool calls and its corresponding tool result
/// messages are always removed together. [MinimumPreservedGroups] is a hard
/// floor: even if the [Target] has not been reached, compaction will not
/// touch the last [MinimumPreservedGroups] non-system groups. The
/// [CompactionTrigger] controls when compaction proceeds. Use
/// [CompactionTriggers] for common trigger conditions such as token or group
/// thresholds.
class TruncationCompactionStrategy extends CompactionStrategy {
  /// Initializes a new instance of the [TruncationCompactionStrategy] class.
  ///
  /// [trigger] The [CompactionTrigger] that controls when compaction proceeds.
  ///
  /// [minimumPreservedGroups] The minimum number of most-recent non-system
  /// message groups to preserve. This is a hard floor — compaction will not
  /// remove groups beyond this limit, regardless of the target condition.
  ///
  /// [target] An optional target condition that controls when compaction stops.
  /// When `null`, defaults to the inverse of the `trigger` — compaction stops
  /// as soon as the trigger would no longer fire.
  TruncationCompactionStrategy(
    super.trigger, {
    int? minimumPreservedGroups,
    super.target,
  }) {
    this.minimumPreservedGroups = CompactionStrategy.ensureNonNegative(
      minimumPreservedGroups,
    );
  }

  /// Gets the minimum number of most-recent non-system message groups that are
  /// always preserved. This is a hard floor that compaction cannot exceed,
  /// regardless of the target condition.
  late final int minimumPreservedGroups;

  @override
  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  ) async {
    var removableCount = 0;
    for (var i = 0; i < index.groups.length; i++) {
      var group = index.groups[i];
      if (!group.isExcluded && group.kind != CompactionGroupKind.system) {
        removableCount++;
      }
    }
    var maxRemovable = removableCount - minimumPreservedGroups;
    if (maxRemovable <= 0) {
      return false;
    }
    var compacted = false;
    var removed = 0;
    for (var i = 0; i < index.groups.length && removed < maxRemovable; i++) {
      var group = index.groups[i];
      if (group.isExcluded || group.kind == CompactionGroupKind.system) {
        continue;
      }
      group.isExcluded = true;
      group.excludeReason = 'Truncated by ${'TruncationCompactionStrategy'}';
      removed++;
      compacted = true;
      if (target(index)) {
        break;
      }
    }
    return compacted;
  }
}
