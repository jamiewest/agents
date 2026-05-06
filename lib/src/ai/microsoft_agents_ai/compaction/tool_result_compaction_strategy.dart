import 'package:extensions/system.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/ai.dart';
import '../../../func_typedefs.dart';
// TODO: import not yet ported
import 'compaction_group_kind.dart';
import 'compaction_message_group.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';
import 'compaction_trigger.dart';
import 'compaction_triggers.dart';

/// A compaction strategy that collapses old tool call groups into single
/// concise assistant messages, removing the detailed tool results while
/// preserving a record of which tools were called and what they returned.
///
/// Remarks: This is the gentlest compaction strategy — it does not remove any
/// user messages or plain assistant responses. It only targets [ToolCall]
/// groups outside the protected recent window, replacing each multi-message
/// group (assistant call + tool results) with a single assistant message in a
/// YAML-like format: [Tool Calls] get_weather: - Sunny and 72°F search_docs:
/// - Found 3 docs A custom [ToolCallFormatter] can be supplied to override
/// the default YAML-like summary format. The formatter receives the
/// [CompactionMessageGroup] being collapsed and must return the replacement
/// summary String. [CompactionMessageGroup)] is the built-in default and can
/// be reused inside a custom formatter when needed. [MinimumPreservedGroups]
/// is a hard floor: even if the [Target] has not been reached, compaction
/// will not touch the last [MinimumPreservedGroups] non-system groups. The
/// [CompactionTrigger] predicate controls when compaction proceeds. Use
/// [CompactionTriggers] for common trigger conditions such as token
/// thresholds.
class ToolResultCompactionStrategy extends CompactionStrategy {
  /// Initializes a new instance of the [ToolResultCompactionStrategy] class.
  ///
  /// [trigger] The [CompactionTrigger] that controls when compaction proceeds.
  ///
  /// [minimumPreservedGroups] The minimum number of most-recent non-system
  /// message groups to preserve. This is a hard floor — compaction will not
  /// collapse groups beyond this limit, regardless of the target condition.
  /// Defaults to [DefaultMinimumPreserved], ensuring the current turn's tool
  /// interactions remain visible.
  ///
  /// [target] An optional target condition that controls when compaction stops.
  /// When `null`, defaults to the inverse of the `trigger` — compaction stops
  /// as soon as the trigger would no longer fire.
  ToolResultCompactionStrategy(
    CompactionTrigger trigger,
    {int? minimumPreservedGroups = null, CompactionTrigger? target = null, }
  ) : super(trigger, target: target) {
    this.minimumPreservedGroups = ensureNonNegative(minimumPreservedGroups);
  }

  /// Gets the minimum number of most-recent non-system groups that are always
  /// preserved. This is a hard floor that compaction cannot exceed, regardless
  /// of the target condition.
  late final int minimumPreservedGroups;

  /// An optional custom formatter that converts a [CompactionMessageGroup] into
  /// a summary String. When `null`, [CompactionMessageGroup)] is used, which
  /// produces a YAML-like block listing each tool name and its results.
  Func<CompactionMessageGroup, String>? toolCallFormatter;

  @override
  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  ) {
    var nonSystemIncludedIndices = [];
    for (var i = 0; i < index.groups.length; i++) {
      var group = index.groups[i];
      if (!group.isExcluded && group.kind != CompactionGroupKind.system) {
        nonSystemIncludedIndices.add(i);
      }
    }
    var protectedStart = ensureNonNegative(nonSystemIncludedIndices.length - this.minimumPreservedGroups);
    var protectedGroupIndices = [];
    for (var i = protectedStart; i < nonSystemIncludedIndices.length; i++) {
      protectedGroupIndices.add(nonSystemIncludedIndices[i]);
    }
    var eligibleIndices = [];
    for (var i = 0; i < index.groups.length; i++) {
      var group = index.groups[i];
      if (!group.isExcluded && group.kind == CompactionGroupKind.toolCall && !protectedGroupIndices.contains(i)) {
        eligibleIndices.add(i);
      }
    }
    if (eligibleIndices.length == 0) {
      return Future<bool>(false);
    }
    var compacted = false;
    var offset = 0;
    for (var e = 0; e < eligibleIndices.length; e++) {
      var idx = eligibleIndices[e] + offset;
      var group = index.groups[idx];
      var summary = (this.toolCallFormatter ?? DefaultToolCallFormatter).invoke(group);
      // Exclude the original group and insert a collapsed replacement
            group.isExcluded = true;
      group.excludeReason = 'Collapsed by ${'ToolResultCompactionStrategy'}';
      var summaryMessage = ChatMessage.fromText(ChatRole.assistant, summary);
      (summaryMessage.additionalProperties ??= [])[CompactionMessageGroup.summaryPropertyKey] = true;
      index.insertGroup(idx + 1, CompactionGroupKind.summary, [summaryMessage], group.turnIndex);
      offset++;
      compacted = true;
      if (this.target(index)) {
        break;
      }
    }
    return Future<bool>(compacted);
  }

  /// The default formatter that produces a YAML-like summary of tool call
  /// groups, including tool names, results, and deduplication counts for
  /// repeated tool names.
  ///
  /// Remarks: This is the formatter used when no custom [ToolCallFormatter] is
  /// supplied. It can be referenced directly in a custom formatter to augment
  /// or wrap the default output.
  static String defaultToolCallFormatter(CompactionMessageGroup group) {
    var functionCalls = [];
    var resultsByCallId = [];
    var plainTextResults = [];
    for (final message in group.messages) {
      if (message.contents == null) {
        continue;
      }
      var hasFunctionResult = false;
      for (final content in message.contents) {
        if (content is FunctionCallContent) {
          final fcc = content as FunctionCallContent;
          functionCalls.add((fcc.callId, fcc.name));
        } else if (content is FunctionResultContent && frc.callId != null) {
          resultsByCallId[frc.callId] = frc.result?.toString() ?? '';
          hasFunctionResult = true;
        }
      }
      if (!hasFunctionResult && message.role == ChatRole.tool && message.text is String) {
        final text = !hasFunctionResult && message.role == ChatRole.tool && message.text as String;
        plainTextResults.add(text);
      }
    }
    var plainTextIdx = 0;
    var orderedNames = [];
    var groupedResults = [];
    /* TODO: unsupported node kind "unknown" */
    // foreach ((String callId, String name) in functionCalls)
    //         {
      //             if (!groupedResults.TryGetValue(name, _))
      //             {
        //                 orderedNames.Add(name);
        //                 groupedResults[name] = [];
        //             }
      //
      //             String? result = null;
      //             if (resultsByCallId.TryGetValue(callId, matchedResult))
      //             {
        //                 result = matchedResult;
        //             }
      //             else if (plainTextIdx < plainTextResults.Count)
      //             {
        //                 result = plainTextResults[plainTextIdx++];
        //             }
      //
      //             if (!String.IsNullOrEmpty(result))
      //             {
        //                 groupedResults[name].Add(result);
        //             }
      //         }
    var lines = ["[Tool Calls]"];
    for (final name in orderedNames) {
      var results = groupedResults[name];
      lines.add('${name}:');
      if (results.length > 0) {
        for (final result in results) {
          lines.add('  - ${result}');
        }
      }
    }
    return lines.join("\n");
  }
}
