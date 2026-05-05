import 'package:extensions/ai.dart';
import 'compaction_group_kind.dart';
import 'compaction_message_index.dart';

/// Represents a logical group of [ChatMessage] instances that must be kept or
/// removed together during compaction.
///
/// Remarks: Message groups ensure atomic preservation of related messages.
/// For example, an assistant message containing tool calls and its
/// corresponding tool result messages form a [ToolCall] group — removing one
/// without the other would cause LLM API errors. Groups also support
/// exclusion semantics: a group can be marked as excluded (with an optional
/// reason) to indicate it should not be included in the messages sent to the
/// model, while still being preserved for diagnostics, storage, or later
/// re-inclusion. Each group tracks its [MessageCount], [ByteCount], and
/// [TokenCount] so that [CompactionMessageIndex] can efficiently aggregate
/// totals across all or only included groups.
class CompactionMessageGroup {
  /// Initializes a new instance of the [CompactionMessageGroup] class.
  ///
  /// [kind] The kind of message group.
  ///
  /// [messages] The messages in this group. The list is captured as a read-only
  /// snapshot.
  ///
  /// [byteCount] The total UTF-8 byte count of the text content in the
  /// messages.
  ///
  /// [tokenCount] The token count for the messages, computed by a tokenizer or
  /// estimated.
  ///
  /// [turnIndex] The user turn this group belongs to, or `null` for [System].
  CompactionMessageGroup(
    CompactionGroupKind kind,
    List<ChatMessage> messages,
    int byteCount,
    int tokenCount, {
    int? turnIndex = null,
  }) : kind = kind,
       messages = messages,
       byteCount = byteCount,
       tokenCount = tokenCount {
    this.messageCount = messages.length;
    this.turnIndex = turnIndex;
  }

  /// The [AdditionalProperties] key used to identify a message as a compaction
  /// summary.
  ///
  /// Remarks: When this key is present with a value of `true`, the message is
  /// classified as [Summary] by [Nullable{Tokenizer})].
  static final String summaryPropertyKey = "_is_summary";

  /// Gets the kind of this message group.
  final CompactionGroupKind kind;

  /// Gets the messages in this group.
  final List<ChatMessage> messages;

  /// Gets the number of messages in this group.
  late final int messageCount;

  /// Gets the total UTF-8 byte count of the text content in this group's
  /// messages.
  final int byteCount;

  /// Gets the estimated or actual token count for this group's messages.
  final int tokenCount;

  /// Gets user turn index this group belongs to, or `null` for groups that
  /// precede the first user message (e.g., system messages). A turn index of 0
  /// corresponds with any non-system message that precedes the first user
  /// message, turn index 1 corresponds with the first user message and its
  /// subsequent non-user messages, and so on...
  ///
  /// Remarks: A turn starts with a [User] group and includes all subsequent
  /// non-user, non-system groups until the next user group or end of
  /// conversation. System messages ([System]) are always assigned a `null` turn
  /// index since they never belong to a user turn.
  late final int? turnIndex;

  /// Gets or sets a value indicating whether this group is excluded from the
  /// projected message list.
  ///
  /// Remarks: Excluded groups are preserved in the collection for diagnostics
  /// or storage purposes but are not included when calling
  /// [GetIncludedMessages].
  bool isExcluded;

  /// Gets or sets an optional reason explaining why this group was excluded.
  String? excludeReason;
}
