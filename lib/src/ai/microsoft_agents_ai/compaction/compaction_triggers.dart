import 'compaction_group_kind.dart';
import 'compaction_message_index.dart';
import 'compaction_trigger.dart';

/// Factory methods for [CompactionTrigger] predicates.
class CompactionTriggers {
  CompactionTriggers._();

  static bool always(CompactionMessageIndex index) => true;
  static bool never(CompactionMessageIndex index) => false;

  static CompactionTrigger tokensBelow(int maxTokens) =>
      (index) => index.includedTokenCount < maxTokens;

  static CompactionTrigger tokensExceed(int maxTokens) =>
      (index) => index.includedTokenCount > maxTokens;

  static CompactionTrigger messagesExceed(int maxMessages) =>
      (index) => index.includedMessageCount > maxMessages;

  static CompactionTrigger turnsExceed(int maxTurns) =>
      (index) => index.includedTurnCount > maxTurns;

  static CompactionTrigger groupsExceed(int maxGroups) =>
      (index) => index.includedGroupCount > maxGroups;

  static CompactionTrigger hasToolCalls() {
    return (index) => index.groups.any(
      (group) =>
          !group.isExcluded && group.kind == CompactionGroupKind.toolCall,
    );
  }

  static CompactionTrigger all(List<CompactionTrigger> triggers) {
    return (index) => triggers.every((trigger) => trigger(index));
  }

  static CompactionTrigger any(List<CompactionTrigger> triggers) {
    return (index) => triggers.any((trigger) => trigger(index));
  }
}
