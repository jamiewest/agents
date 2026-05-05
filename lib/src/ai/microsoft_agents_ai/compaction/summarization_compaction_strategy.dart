import 'dart:math';
import 'package:extensions/system.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/ai.dart';
import 'compaction_group_kind.dart';
import 'compaction_message_group.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';
import 'compaction_telemetry.dart';
import 'compaction_trigger.dart';
import 'compaction_triggers.dart';

/// A compaction strategy that uses an LLM to summarize older portions of the
/// conversation, replacing them with a single summary message that preserves
/// key facts and context.
///
/// Remarks: This strategy protects system messages and the most recent
/// [MinimumPreservedGroups] non-system groups. All older groups are collected
/// and sent to the [ChatClient] for summarization. The resulting summary
/// replaces those messages as a single assistant message with [Summary].
/// [MinimumPreservedGroups] is a hard floor: even if the [Target] has not
/// been reached, compaction will not touch the last [MinimumPreservedGroups]
/// non-system groups. The [CompactionTrigger] predicate controls when
/// compaction proceeds. Use [CompactionTriggers] for common trigger
/// conditions such as token thresholds.
class SummarizationCompactionStrategy extends CompactionStrategy {
  /// Initializes a new instance of the [SummarizationCompactionStrategy] class.
  ///
  /// [chatClient] The [ChatClient] to use for generating summaries. A smaller,
  /// faster model is recommended.
  ///
  /// [trigger] The [CompactionTrigger] that controls when compaction proceeds.
  ///
  /// [minimumPreservedGroups] The minimum number of most-recent non-system
  /// message groups to preserve. This is a hard floor — compaction will not
  /// summarize groups beyond this limit, regardless of the target condition.
  /// Defaults to 8, preserving the current and recent exchanges.
  ///
  /// [summarizationPrompt] An optional custom system prompt for the
  /// summarization LLM call. When `null`, [DefaultSummarizationPrompt] is used.
  ///
  /// [target] An optional target condition that controls when compaction stops.
  /// When `null`, defaults to the inverse of the `trigger` — compaction stops
  /// as soon as the trigger would no longer fire.
  SummarizationCompactionStrategy(
    ChatClient chatClient,
    CompactionTrigger trigger,
    {int? minimumPreservedGroups = null, String? summarizationPrompt = null, CompactionTrigger? target = null, },
  ) : chatClient = chatClient {
    this.minimumPreservedGroups = ensureNonNegative(minimumPreservedGroups);
    this.summarizationPrompt = summarizationPrompt ?? DefaultSummarizationPrompt;
  }

  /// Gets the chat client used for generating summaries.
  final ChatClient chatClient;

  /// Gets the minimum number of most-recent non-system groups that are always
  /// preserved. This is a hard floor that compaction cannot exceed, regardless
  /// of the target condition.
  late final int minimumPreservedGroups;

  /// Gets the prompt used when requesting summaries from the chat client.
  late final String summarizationPrompt;

  @override
  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  ) async  {
    var nonSystemIncludedCount = 0;
    for (var i = 0; i < index.groups.length; i++) {
      var group = index.groups[i];
      if (!group.isExcluded && group.kind != CompactionGroupKind.system) {
        nonSystemIncludedCount++;
      }
    }
    var protectedFromEnd = min(this.minimumPreservedGroups, nonSystemIncludedCount);
    var maxSummarizable = nonSystemIncludedCount - protectedFromEnd;
    if (maxSummarizable <= 0) {
      return false;
    }
    var summarizationMessages = [ChatMessage.fromText(ChatRole.system, this.summarizationPrompt)];
    var excludedGroups = [];
    var insertIndex = -1;
    for (var i = 0; i < index.groups.length && excludedGroups.length < maxSummarizable; i++) {
      var group = index.groups[i];
      if (group.isExcluded || group.kind == CompactionGroupKind.system) {
        continue;
      }
      if (insertIndex < 0) {
        insertIndex = i;
      }
      // Collect messages from this group for summarization
            summarizationMessages.addAll(group.messages);
      group.isExcluded = true;
      group.excludeReason = 'Summarized by ${'SummarizationCompactionStrategy'}';
      excludedGroups.add(group);
      if (this.target(index)) {
        break;
      }
    }
    var summarized = excludedGroups.length;
    if (logger.isEnabled(LogLevel.debug)) {
      logger.logSummarizationStarting(
        summarized,
        summarizationMessages.length - 1,
        this.chatClient.runtimeType.toString(),
      );
    }
    var summarizeActivity = CompactionTelemetry.activitySource.startActivity(CompactionTelemetry.activityNames.summarize);
    summarizeActivity?.setTag(CompactionTelemetry.tags.groupsSummarized, summarized);
    ChatResponse response;
    try {
      response = await this.chatClient.getResponseAsync(
                summarizationMessages,
                cancellationToken: cancellationToken);
    } catch (e, s) {
      if (e is Exception) {
        final ex = e as Exception;
        {
          for (var i = 0; i < excludedGroups.length; i++) {
            excludedGroups[i].isExcluded = false;
            excludedGroups[i].excludeReason = null;
          }
          logger.logSummarizationFailed(summarized, ex.message);
          return false;
        }
      } else {
        rethrow;
      }
    }
    var summaryText = (response.text == null || response.text.trim().isEmpty) ? "[Summary unavailable]" : response.text;
    summarizeActivity?.setTag(CompactionTelemetry.tags.summaryLength, summaryText.length);
    var summaryMessage = new(ChatRole.assistant, '[Summary]\n${summaryText}');
    (summaryMessage.additionalProperties ??= [])[CompactionMessageGroup.summaryPropertyKey] = true;
    index.insertGroup(insertIndex, CompactionGroupKind.summary, [summaryMessage]);
    logger.logSummarizationCompleted(summaryText.length, insertIndex);
    return true;
  }
}
