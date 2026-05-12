import 'package:extensions/ai.dart';
import 'compaction_message_group.dart';

/// Identifies the kind of a [CompactionMessageGroup].
///
/// Remarks: Message groups are used to classify logically related messages
/// that must be kept together during compaction operations. For example, an
/// assistant message containing tool calls and its corresponding tool result
/// messages form an atomic [ToolCall] group.
enum CompactionGroupKind {
  /// A system message group containing one or more system messages.
  system,

  /// A user message group containing a single user message.
  user,

  /// An assistant message group containing a single assistant text response (no
  /// tool calls).
  assistantText,

  /// An atomic tool call group containing an assistant message with tool calls
  /// followed by the corresponding tool result messages.
  ///
  /// Remarks: This group must be treated as an atomic unit during compaction.
  /// Removing the assistant message without its tool results (or vice versa)
  /// will cause LLM API errors.
  toolCall,

  /// A summary message group produced by a compaction strategy (e.g.,
  /// `SummarizationCompactionStrategy`).
  ///
  /// Remarks: Summary groups replace previously compacted messages with a
  /// condensed representation. They are identified by the [SummaryPropertyKey]
  /// metadata entry on the underlying [ChatMessage].
  summary,
}
