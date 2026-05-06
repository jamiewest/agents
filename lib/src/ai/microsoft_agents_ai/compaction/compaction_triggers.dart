import 'compaction_group_kind.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';
import 'compaction_trigger.dart';

/// Factory to create [CompactionTrigger] predicates.
///
/// Remarks: A [CompactionTrigger] defines a condition based on
/// [CompactionMessageIndex] metrics used by a [CompactionStrategy] to
/// determine when to trigger compaction and when the target compaction
/// threshold has been met. Combine triggers with [CompactionTrigger[])] or
/// [CompactionTrigger[])] for compound conditions.
class CompactionTriggers {
  CompactionTriggers();

  /// Always trigger, regardless of the message index state.
  static final CompactionTrigger always =(_) => true;

  /// Never trigger, regardless of the message index state.
  static final CompactionTrigger never =(_) => false;

  /// Creates a trigger that fires when the included token count is below the
  /// specified maximum.
  ///
  /// Returns: A [CompactionTrigger] that evaluates included token count.
  ///
  /// [maxTokens] The token threshold.
  static CompactionTrigger tokensBelow(int maxTokens) {
    return (index) => index.includedTokenCount < maxTokens;
  }

  /// Creates a trigger that fires when the included token count exceeds the
  /// specified maximum.
  ///
  /// Returns: A [CompactionTrigger] that evaluates included token count.
  ///
  /// [maxTokens] The token threshold.
  static CompactionTrigger tokensExceed(int maxTokens) {
    return (index) => index.includedTokenCount > maxTokens;
  }

  /// Creates a trigger that fires when the included message count exceeds the
  /// specified maximum.
  ///
  /// Returns: A [CompactionTrigger] that evaluates included message count.
  ///
  /// [maxMessages] The message threshold.
  static CompactionTrigger messagesExceed(int maxMessages) {
    return (index) => index.includedMessageCount > maxMessages;
  }

  /// Creates a trigger that fires when the included user turn count exceeds the
  /// specified maximum.
  ///
  /// Remarks: A user turn starts with a [User] group and includes all
  /// subsequent non-user, non-system groups until the next user group or end of
  /// conversation. Each group is assigned a [TurnIndex] indicating which user
  /// turn it belongs to. System messages ([System]) are always assigned a
  /// `null` [TurnIndex] since they never belong to a user turn. The turn count
  /// is the number of distinct values defined by [TurnIndex].
  ///
  /// Returns: A [CompactionTrigger] that evaluates included turn count.
  ///
  /// [maxTurns] The turn threshold.
  static CompactionTrigger turnsExceed(int maxTurns) {
    return (index) => index.includedTurnCount > maxTurns;
  }

  /// Creates a trigger that fires when the included group count exceeds the
  /// specified maximum.
  ///
  /// Returns: A [CompactionTrigger] that evaluates included group count.
  ///
  /// [maxGroups] The group threshold.
  static CompactionTrigger groupsExceed(int maxGroups) {
    return (index) => index.includedGroupCount > maxGroups;
  }

  /// Creates a trigger that fires when the included message index contains at
  /// least one non-excluded [ToolCall] group.
  ///
  /// Returns: A [CompactionTrigger] that evaluates included tool call presence.
  static CompactionTrigger hasToolCalls() {
    return (index) => index.groups.any((g) => !g.isExcluded && g.kind == CompactionGroupKind.toolCall);
  }

  /// Creates a compound trigger that fires only when all of the specified
  /// triggers fire.
  ///
  /// Returns: A [CompactionTrigger] that requires all conditions to be met.
  ///
  /// [triggers] The triggers to combine with logical AND.
  static CompactionTrigger all(List<CompactionTrigger> triggers) {
    return (index) {
        
            for (int i = 0; i < triggers.length; i++)
            {
                if (!triggers[i](index))
                {
                    return false;
        }
      }

            return true;
        };
  }

  /// Creates a compound trigger that fires when any of the specified triggers
  /// fire.
  ///
  /// Returns: A [CompactionTrigger] that requires at least one condition to be
  /// met.
  ///
  /// [triggers] The triggers to combine with logical OR.
  static CompactionTrigger any(List<CompactionTrigger> triggers) {
    return (index) {
        
            for (int i = 0; i < triggers.length; i++)
            {
                if (triggers[i](index))
                {
                    return true;
        }
      }

            return false;
        };
  }
}
