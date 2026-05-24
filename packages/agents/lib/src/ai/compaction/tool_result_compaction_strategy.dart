import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import 'compaction_group_kind.dart';
import 'compaction_message_group.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';

/// Formats a [CompactionMessageGroup] representing a tool-call exchange
/// into a concise summary string.
typedef ToolCallFormatter = String Function(CompactionMessageGroup group);

/// A compaction strategy that collapses old tool call groups into single
/// concise assistant messages.
class ToolResultCompactionStrategy extends CompactionStrategy {
  ToolResultCompactionStrategy(
    super.trigger, {
    int? minimumPreservedGroups,
    ToolCallFormatter? toolCallFormatter,
    super.target,
  }) : toolCallFormatter =
           toolCallFormatter ??
           ToolResultCompactionStrategy.defaultToolCallFormatter {
    this.minimumPreservedGroups = CompactionStrategy.ensureNonNegative(
      minimumPreservedGroups,
    );
  }

  late final int minimumPreservedGroups;
  final ToolCallFormatter toolCallFormatter;

  @override
  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  ) async {
    final nonSystemIncludedIndices = <int>[];
    for (var i = 0; i < index.groups.length; i++) {
      final group = index.groups[i];
      if (!group.isExcluded && group.kind != CompactionGroupKind.system) {
        nonSystemIncludedIndices.add(i);
      }
    }

    final protectedStart = CompactionStrategy.ensureNonNegative(
      nonSystemIncludedIndices.length - minimumPreservedGroups,
    );
    final protectedGroupIndices = nonSystemIncludedIndices
        .skip(protectedStart)
        .toSet();

    final eligibleIndices = <int>[];
    for (var i = 0; i < index.groups.length; i++) {
      final group = index.groups[i];
      if (!group.isExcluded &&
          group.kind == CompactionGroupKind.toolCall &&
          !protectedGroupIndices.contains(i)) {
        eligibleIndices.add(i);
      }
    }

    if (eligibleIndices.isEmpty) {
      return false;
    }

    var compacted = false;
    var offset = 0;
    for (final eligibleIndex in eligibleIndices) {
      final groupIndex = eligibleIndex + offset;
      final group = index.groups[groupIndex];
      final summary = toolCallFormatter(group);

      group.isExcluded = true;
      group.excludeReason = 'Collapsed by ToolResultCompactionStrategy';

      final summaryMessage = ChatMessage.fromText(ChatRole.assistant, summary);
      (summaryMessage.additionalProperties ??=
              <String, Object?>{})[CompactionMessageGroup.summaryPropertyKey] =
          true;

      index.insertGroup(groupIndex + 1, CompactionGroupKind.summary, [
        summaryMessage,
      ], turnIndex: group.turnIndex);
      offset++;
      compacted = true;

      if (target(index)) {
        break;
      }
    }

    return compacted;
  }

  static String defaultToolCallFormatter(CompactionMessageGroup group) {
    final functionCalls = <({String callId, String name})>[];
    final resultsByCallId = <String, String>{};
    final plainTextResults = <String>[];

    for (final message in group.messages) {
      var hasFunctionResult = false;
      for (final content in message.contents) {
        if (content is FunctionCallContent) {
          functionCalls.add((callId: content.callId, name: content.name));
        } else if (content is FunctionResultContent) {
          resultsByCallId[content.callId] = content.result?.toString() ?? '';
          hasFunctionResult = true;
        }
      }

      if (!hasFunctionResult &&
          message.role == ChatRole.tool &&
          message.text.isNotEmpty) {
        plainTextResults.add(message.text);
      }
    }

    final orderedNames = <String>[];
    final groupedResults = <String, List<String>>{};
    var plainTextIndex = 0;

    for (final functionCall in functionCalls) {
      groupedResults.putIfAbsent(functionCall.name, () {
        orderedNames.add(functionCall.name);
        return <String>[];
      });

      final result =
          resultsByCallId[functionCall.callId] ??
          (plainTextIndex < plainTextResults.length
              ? plainTextResults[plainTextIndex++]
              : null);

      if (result != null && result.isNotEmpty) {
        groupedResults[functionCall.name]!.add(result);
      }
    }

    final lines = <String>['[Tool Calls]'];
    for (final name in orderedNames) {
      lines.add('$name:');
      for (final result in groupedResults[name]!) {
        lines.add('  - $result');
      }
    }

    return lines.join('\n');
  }
}
