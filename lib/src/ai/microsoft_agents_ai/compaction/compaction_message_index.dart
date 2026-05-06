import 'dart:convert';
import 'package:extensions/ai.dart';
import 'compaction_group_kind.dart';
import 'compaction_message_group.dart';
import '../../../map_extensions.dart';

/// A collection of [CompactionMessageGroup] instances and derived metrics
/// based on a flat list of [ChatMessage] objects.
///
/// Remarks: [CompactionMessageIndex] provides structural grouping of messages
/// into logical [CompactionMessageGroup] units. Individual groups can be
/// marked as excluded without being removed, allowing compaction strategies
/// to toggle visibility while preserving the full history for diagnostics or
/// storage. Metrics are provided both including and excluding excluded
/// groups, allowing strategies to make informed decisions based on the impact
/// of potential exclusions.
class CompactionMessageIndex {
  /// Initializes a new instance of the [CompactionMessageIndex] class with the
  /// specified groups.
  ///
  /// [groups] The message groups.
  ///
  /// [tokenizer] An optional tokenizer retained for computing token counts when
  /// adding new groups.
  CompactionMessageIndex(
    List<CompactionMessageGroup> groups,
    {Tokenizer? tokenizer = null, }
  ) : groups = groups {
    this.tokenizer = tokenizer;
    for (var index = groups.length - 1; index >= 0; --index) {
      if (this._lastProcessedMessage == null && this.groups[index].kind != CompactionGroupKind.summary) {
        var groupMessages = this.groups[index].messages;
        this._lastProcessedMessage = groupMessages.last;
      }
      if (this.groups[index].turnIndex != null) {
        this._currentTurn = this.groups[index].turnIndex!.value;
        if (this._lastProcessedMessage != null) {
          break;
        }
      }
    }
  }

  late int _currentTurn;

  late ChatMessage? _lastProcessedMessage;

  /// Gets the list of message groups in this collection.
  final List<CompactionMessageGroup> groups;

  /// Gets the tokenizer used for computing token counts, or `null` if token
  /// counts are estimated.
  late final Tokenizer? tokenizer;

  /// Creates a [CompactionMessageIndex] from a flat list of [ChatMessage]
  /// instances.
  ///
  /// Remarks: The grouping algorithm: System messages become [System] groups.
  /// User messages become [User] groups. Assistant messages with tool calls,
  /// followed by their corresponding tool result messages, become [ToolCall]
  /// groups. Assistant messages marked with [SummaryPropertyKey] become
  /// [Summary] groups. Assistant messages without tool calls become
  /// [AssistantText] groups.
  ///
  /// Returns: A new [CompactionMessageIndex] with messages organized into
  /// logical groups.
  ///
  /// [messages] The messages to group.
  ///
  /// [tokenizer] An optional [Tokenizer] for computing token counts on each
  /// group. When `null`, token counts are estimated as `ByteCount / 4`.
  static CompactionMessageIndex create(List<ChatMessage> messages, {Tokenizer? tokenizer, }) {
    var instance = new([], tokenizer);
    instance.appendFromMessages(messages, 0);
    return instance;
  }

  /// Incrementally updates the groups with new messages from the conversation.
  ///
  /// Remarks: Uses equality on the last processed message to detect changes.
  /// Only the messages after that position are processed and appended as new
  /// groups. Existing groups and their compaction state (exclusions) are
  /// preserved. If the last processed message is not found (e.g., the message
  /// list was replaced entirely or a sliding window shifted past it), all
  /// groups are cleared and rebuilt from scratch. If the last message in
  /// `allMessages` matches the last processed message, no work is performed.
  ///
  /// [allMessages] The full list of messages for the conversation. This must be
  /// the same list (or a replacement with the same prefix) that was used to
  /// create or last update this instance.
  void update(List<ChatMessage> allMessages) {
    if (allMessages.length == 0) {
      this.groups.clear();
      this._currentTurn = 0;
      this._lastProcessedMessage = null;
      return;
    }
    if (this._lastProcessedMessage != null &&
            allMessages.length >= this.rawMessageCount &&
            allMessages[allMessages.length - 1].contentEquals(this._lastProcessedMessage)) {
      return;
    }
    var foundIndex = -1;
    if (this._lastProcessedMessage != null) {
      for (var i = allMessages.length - 1; i >= 0; --i) {
        if (allMessages[i].contentEquals(this._lastProcessedMessage)) {
          foundIndex = i;
          break;
        }
      }
    }
    if (foundIndex < 0) {
      // Last processed message not found — total rebuild.
            this.groups.clear();
      this._currentTurn = 0;
      this.appendFromMessages(allMessages, 0);
      return;
    }
    if (foundIndex + 1 < this.rawMessageCount) {
      // Front of the message list was trimmed — rebuild.
            this.groups.clear();
      this._currentTurn = 0;
      this.appendFromMessages(allMessages, 0);
      return;
    }
    // Process only the delta messages.
        this.appendFromMessages(allMessages, foundIndex + 1);
  }

  void appendFromMessages(List<ChatMessage> messages, int startIndex, ) {
    var index = startIndex;
    while (index < messages.length) {
      var message = messages[index];
      if (message.role == ChatRole.system) {
        // System messages are not part of any turn
                this.groups.add(createGroup(CompactionGroupKind.system, [message], this.tokenizer, turnIndex: null));
        index++;
      } else if (message.role == ChatRole.user) {
        this._currentTurn++;
        this.groups.add(createGroup(CompactionGroupKind.user, [message], this.tokenizer, this._currentTurn));
        index++;
      } else if (message.role == ChatRole.assistant && hasToolCalls(message)) {
        var groupMessages = [message];
        index++;
        while (index < messages.length &&
                       (messages[index].role == ChatRole.tool ||
                        (messages[index].role == ChatRole.assistant && hasOnlyReasoning(messages[index])))) {
          groupMessages.add(messages[index]);
          index++;
        }
        this.groups.add(createGroup(CompactionGroupKind.toolCall, groupMessages, this.tokenizer, this._currentTurn));
      } else if (message.role == ChatRole.assistant && isSummaryMessage(message)) {
        this.groups.add(createGroup(CompactionGroupKind.summary, [message], this.tokenizer, this._currentTurn));
        index++;
      } else if (message.role == ChatRole.assistant && hasOnlyReasoning(message)) {
        var lookahead = index + 1;
        while (lookahead < messages.length &&
                       messages[lookahead].role == ChatRole.assistant &&
                       hasOnlyReasoning(messages[lookahead])) {
          lookahead++;
        }
        if (lookahead < messages.length && messages[lookahead].role == ChatRole.assistant && hasToolCalls(messages[lookahead])) {
          var groupMessages = [];
          for (var j = index; j <= lookahead; j++) {
            groupMessages.add(messages[j]);
          }
          index = lookahead + 1;
          while (index < messages.length &&
                           (messages[index].role == ChatRole.tool ||
                            (messages[index].role == ChatRole.assistant && hasOnlyReasoning(messages[index])))) {
            groupMessages.add(messages[index]);
            index++;
          }
          this.groups.add(createGroup(CompactionGroupKind.toolCall, groupMessages, this.tokenizer, this._currentTurn));
        } else {
          this.groups.add(createGroup(CompactionGroupKind.assistantText, [message], this.tokenizer, this._currentTurn));
          index++;
        }
      } else {
        this.groups.add(createGroup(CompactionGroupKind.assistantText, [message], this.tokenizer, this._currentTurn));
        index++;
      }
    }
    if (messages.length > 0) {
      this._lastProcessedMessage = messages.last;
    }
  }

  /// Creates a new [CompactionMessageGroup] with byte and token counts computed
  /// using this collection's [Tokenizer], and adds it to the [Groups] list at
  /// the specified index.
  ///
  /// Returns: The newly created [CompactionMessageGroup].
  ///
  /// [index] The zero-based index at which the group should be inserted.
  ///
  /// [kind] The kind of message group.
  ///
  /// [messages] The messages in the group.
  ///
  /// [turnIndex] The optional turn index to assign to the new group.
  CompactionMessageGroup insertGroup(
    int index,
    CompactionGroupKind kind,
    List<ChatMessage> messages,
    {int? turnIndex, }
  ) {
    var group = createGroup(kind, messages, this.tokenizer, turnIndex);
    this.groups.insert(index, group);
    return group;
  }

  /// Creates a new [CompactionMessageGroup] with byte and token counts computed
  /// using this collection's [Tokenizer], and appends it to the end of the
  /// [Groups] list.
  ///
  /// Returns: The newly created [CompactionMessageGroup].
  ///
  /// [kind] The kind of message group.
  ///
  /// [messages] The messages in the group.
  ///
  /// [turnIndex] The optional turn index to assign to the new group.
  CompactionMessageGroup addGroup(
    CompactionGroupKind kind,
    List<ChatMessage> messages,
    {int? turnIndex, }
  ) {
    var group = createGroup(kind, messages, this.tokenizer, turnIndex);
    this.groups.add(group);
    return group;
  }

  /// Returns only the messages from groups that are not excluded.
  ///
  /// Returns: A list of [ChatMessage] instances from included groups, in order.
  Iterable<ChatMessage> getIncludedMessages() {
    return this.groups.where((group) => !group.isExcluded).expand((group) => group.messages);
  }

  /// Returns all messages from all groups, including excluded ones.
  ///
  /// Returns: A list of all [ChatMessage] instances, in order.
  Iterable<ChatMessage> getAllMessages() {
    return this.groups.expand((group) => group.messages);
  }

  /// Gets the total number of groups, including excluded ones.
  int get totalGroupCount {
    return this.groups.length;
  }

  /// Gets the total number of messages across all groups, including excluded
  /// ones.
  int get totalMessageCount {
    return this.groups.fold(0, (a, b) => a + (group(b)) => group.messageCount);
  }

  /// Gets the total UTF-8 byte count across all groups, including excluded
  /// ones.
  int get totalByteCount {
    return this.groups.fold(0, (a, b) => a + (group(b)) => group.byteCount);
  }

  /// Gets the total token count across all groups, including excluded ones.
  int get totalTokenCount {
    return this.groups.fold(0, (a, b) => a + (group(b)) => group.tokenCount);
  }

  /// Gets the total number of groups that are not excluded.
  int get includedGroupCount {
    return this.groups.length((group) => !group.isExcluded);
  }

  /// Gets the total number of messages across all included (non-excluded)
  /// groups.
  int get includedMessageCount {
    return this.groups.where((group) => !group.isExcluded).fold(0, (a, b) => a + (group(b)) => group.messageCount);
  }

  /// Gets the total UTF-8 byte count across all included (non-excluded) groups.
  int get includedByteCount {
    return this.groups.where((group) => !group.isExcluded).fold(0, (a, b) => a + (group(b)) => group.byteCount);
  }

  /// Gets the total token count across all included (non-excluded) groups.
  int get includedTokenCount {
    return this.groups.where((group) => !group.isExcluded).fold(0, (a, b) => a + (group(b)) => group.tokenCount);
  }

  /// Gets the total number of user turns across all groups (including those
  /// with excluded groups).
  int get totalTurnCount {
    return this.groups.map((group) => group.turnIndex).distinct().length((turnIndex) => turnIndex != null && turnIndex > 0);
  }

  /// Gets the number of user turns that have at least one non-excluded group.
  int get includedTurnCount {
    return this.groups.where((group) => !group.isExcluded && group.turnIndex != null && group.turnIndex > 0).map((group) => group.turnIndex).distinct().length();
  }

  /// Gets the total number of groups across all included (non-excluded) groups
  /// that are not [System].
  int get includedNonSystemGroupCount {
    return this.groups.length((group) => !group.isExcluded && group.kind != CompactionGroupKind.system);
  }

  /// Gets the total number of original messages (that are not summaries).
  int get rawMessageCount {
    return this.groups.where((group) => group.kind != CompactionGroupKind.summary).fold(0, (a, b) => a + (group(b)) => group.messageCount);
  }

  /// Returns all groups that belong to the specified user turn.
  ///
  /// Returns: The groups belonging to the turn, in order.
  ///
  /// [turnIndex] The desired turn index.
  Iterable<CompactionMessageGroup> getTurnGroups(int turnIndex) {
    return this.groups.where((group) => group.turnIndex == turnIndex);
  }

  /// Computes the UTF-8 byte count for a set of messages across all content
  /// types.
  ///
  /// Returns: The total UTF-8 byte count of all message content.
  ///
  /// [messages] The messages to compute byte count for.
  static int computeByteCount(List<ChatMessage> messages) {
    var total = 0;
    for (var i = 0; i < messages.length; i++) {
      var contents = messages[i].contents;
      for (var j = 0; j < contents.length; j++) {
        total += computeContentByteCount(contents[j]);
      }
    }
    return total;
  }

  /// Computes the token count for a set of messages using the specified
  /// tokenizer.
  ///
  /// Remarks: Text-bearing content ([TextContent] and [TextReasoningContent])
  /// is tokenized directly. All other content types estimate tokens as
  /// `byteCount / 4`.
  ///
  /// Returns: The total token count across all message content.
  ///
  /// [messages] The messages to compute token count for.
  ///
  /// [tokenizer] The tokenizer to use for counting tokens.
  static int computeTokenCount(List<ChatMessage> messages, Tokenizer tokenizer, ) {
    var total = 0;
    for (var i = 0; i < messages.length; i++) {
      var contents = messages[i].contents;
      for (var j = 0; j < contents.length; j++) {
        var content = contents[j];
        switch (content) {
          case TextContent text:
          if (text.text ?.isNotEmpty == true) {
            total += tokenizer.countTokens(t);
          }
          case TextReasoningContent reasoning:
          if (reasoning.text ?.isNotEmpty == true) {
            total += tokenizer.countTokens(rt);
          }
          if (reasoning.protectedData ?.isNotEmpty == true) {
            total += tokenizer.countTokens(pd);
          }
          default:
          total += computeContentByteCount(content) / 4;
        }
      }
    }
    return total;
  }

  static int computeContentByteCount(AIContent content) {
    switch (content) {
      case TextContent text:
      return getStringByteCount(text.text);
      case TextReasoningContent reasoning:
      return getStringByteCount(reasoning.text) + getStringByteCount(reasoning.protectedData);
      case DataContent data:
      return data.data.length + getStringByteCount(data.mediaType) + getStringByteCount(data.name);
      case UriContent uri:
      return (uri.uri is Uri ? getStringByteCount(uriValue.originalString) : 0) + getStringByteCount(uri.mediaType);
      case FunctionCallContent call:
      var callBytes = getStringByteCount(call.callId) + getStringByteCount(call.name);
      if (call.arguments != null) {
        for (final arg in call.arguments) {
          callBytes += getStringByteCount(arg.key);
          callBytes += getStringByteCount(arg.value?.toString());
        }
      }
      return callBytes;
      case FunctionResultContent result:
      return getStringByteCount(result.callId) + getStringByteCount(result.result?.toString());
      case ErrorContent error:
      return getStringByteCount(error.message) + getStringByteCount(error.errorCode) + getStringByteCount(error.details);
      case HostedFileContent file:
      return getStringByteCount(file.fileId) + getStringByteCount(file.mediaType) + getStringByteCount(file.name);
      default:
      return 0;
    }
  }

  static int getStringByteCount(String? value) {
    return value.isNotEmpty ? utf8.encode(value).length : 0;
  }

  static CompactionMessageGroup createGroup(
    CompactionGroupKind kind,
    List<ChatMessage> messages,
    Tokenizer? tokenizer,
    int? turnIndex,
  ) {
    var byteCount = computeByteCount(messages);
    var tokenCount = tokenizer != null
            ? computeTokenCount(messages, tokenizer)
            : byteCount / 4;
    return CompactionMessageGroup(kind, messages, byteCount, tokenCount, turnIndex);
  }

  static bool hasToolCalls(ChatMessage message) {
    for (final content in message.contents) {
      if (content is FunctionCallContent) {
        return true;
      }
    }
    return false;
  }

  static bool hasOnlyReasoning(ChatMessage message) {
    return message.contents.every((content) => content is TextReasoningContent);
  }

  static bool isSummaryMessage(ChatMessage message) {
    return message.additionalProperties?.tryGetValue(
      CompactionMessageGroup.summaryPropertyKey) is true
            && value is true;
  }
}
