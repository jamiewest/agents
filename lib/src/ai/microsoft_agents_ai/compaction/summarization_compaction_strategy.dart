import 'dart:math';

import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import 'compaction_group_kind.dart';
import 'compaction_log_messages.dart';
import 'compaction_message_group.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';
import 'compaction_telemetry.dart';
import 'compaction_trigger.dart';

/// A compaction strategy that uses an LLM to summarize older portions of the
/// conversation.
class SummarizationCompactionStrategy extends CompactionStrategy {
  SummarizationCompactionStrategy(
    this.chatClient,
    CompactionTrigger trigger, {
    int? minimumPreservedGroups,
    String? summarizationPrompt,
    CompactionTrigger? target,
  }) : super(trigger, target: target) {
    this.minimumPreservedGroups = CompactionStrategy.ensureNonNegative(
      minimumPreservedGroups ?? defaultMinimumPreservedGroups,
    );
    this.summarizationPrompt =
        summarizationPrompt ?? defaultSummarizationPrompt;
  }

  static const int defaultMinimumPreservedGroups = 8;
  static const String defaultSummarizationPrompt =
      'Summarize the following conversation history for use as compacted chat context. '
      'Preserve important facts, decisions, user preferences, open questions, '
      'tool results, and unresolved tasks. Be concise and faithful.';

  final ChatClient chatClient;
  late final int minimumPreservedGroups;
  late final String summarizationPrompt;

  @override
  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  ) async {
    var nonSystemIncludedCount = 0;
    for (final group in index.groups) {
      if (!group.isExcluded && group.kind != CompactionGroupKind.system) {
        nonSystemIncludedCount++;
      }
    }

    final protectedFromEnd = min(
      minimumPreservedGroups,
      nonSystemIncludedCount,
    );
    final maxSummarizable = nonSystemIncludedCount - protectedFromEnd;
    if (maxSummarizable <= 0) {
      return false;
    }

    final summarizationMessages = <ChatMessage>[
      ChatMessage.fromText(ChatRole.system, summarizationPrompt),
    ];
    final excludedGroups = <CompactionMessageGroup>[];
    var insertIndex = -1;

    for (
      var i = 0;
      i < index.groups.length && excludedGroups.length < maxSummarizable;
      i++
    ) {
      final group = index.groups[i];
      if (group.isExcluded || group.kind == CompactionGroupKind.system) {
        continue;
      }

      if (insertIndex < 0) {
        insertIndex = i;
      }

      summarizationMessages.addAll(group.messages);
      group.isExcluded = true;
      group.excludeReason = 'Summarized by SummarizationCompactionStrategy';
      excludedGroups.add(group);

      if (target(index)) {
        break;
      }
    }

    final summarized = excludedGroups.length;
    if (logger.isEnabled(LogLevel.debug)) {
      logger.logSummarizationStarting(
        summarized,
        summarizationMessages.length - 1,
        chatClient.runtimeType.toString(),
      );
    }

    final summarizeActivity = CompactionTelemetry.activitySource.startActivity(
      CompactionTelemetry.activityNames.summarize,
    );
    summarizeActivity?.setTag(
      CompactionTelemetry.tags.groupsSummarized,
      summarized,
    );

    late final ChatResponse response;
    try {
      response = await chatClient.getResponse(
        messages: summarizationMessages,
        cancellationToken: cancellationToken,
      );
    } catch (error) {
      for (final group in excludedGroups) {
        group.isExcluded = false;
        group.excludeReason = null;
      }
      logger.logSummarizationFailed(summarized, error.toString());
      return false;
    }

    final responseText = response.text.trim();
    final summaryText = responseText.isEmpty
        ? '[Summary unavailable]'
        : responseText;
    summarizeActivity?.setTag(
      CompactionTelemetry.tags.summaryLength,
      summaryText.length,
    );

    final summaryMessage = ChatMessage.fromText(
      ChatRole.assistant,
      '[Summary]\n$summaryText',
    );
    (summaryMessage.additionalProperties ??=
            <String, Object?>{})[CompactionMessageGroup.summaryPropertyKey] =
        true;

    index.insertGroup(insertIndex, CompactionGroupKind.summary, [
      summaryMessage,
    ]);
    logger.logSummarizationCompleted(summaryText.length, insertIndex);
    return true;
  }
}
