import 'dart:convert';

import 'package:extensions/ai.dart';

import 'chat_message_content_equality.dart';
import 'compaction_group_kind.dart';
import 'compaction_message_group.dart';

/// Provides token counting for compaction metrics.
abstract class Tokenizer {
  int countTokens(String text);
}

/// A collection of [CompactionMessageGroup] instances and derived metrics
/// based on a flat list of [ChatMessage] objects.
class CompactionMessageIndex {
  CompactionMessageIndex(this.groups, {this.tokenizer}) {
    for (var index = groups.length - 1; index >= 0; --index) {
      final group = groups[index];
      if (_lastProcessedMessage == null &&
          group.kind != CompactionGroupKind.summary &&
          group.messages.isNotEmpty) {
        _lastProcessedMessage = group.messages.last;
      }

      if (group.turnIndex != null) {
        _currentTurn = group.turnIndex!;
        if (_lastProcessedMessage != null) {
          break;
        }
      }
    }
  }

  int _currentTurn = 0;
  ChatMessage? _lastProcessedMessage;

  final List<CompactionMessageGroup> groups;
  final Tokenizer? tokenizer;

  static CompactionMessageIndex create(
    List<ChatMessage> messages, {
    Tokenizer? tokenizer,
  }) {
    final instance = CompactionMessageIndex([], tokenizer: tokenizer);
    instance.appendFromMessages(messages, 0);
    return instance;
  }

  void update(List<ChatMessage> allMessages) {
    if (allMessages.isEmpty) {
      groups.clear();
      _currentTurn = 0;
      _lastProcessedMessage = null;
      return;
    }

    if (_lastProcessedMessage != null &&
        allMessages.length >= rawMessageCount &&
        allMessages.last.contentEquals(_lastProcessedMessage)) {
      return;
    }

    var foundIndex = -1;
    if (_lastProcessedMessage != null) {
      for (var i = allMessages.length - 1; i >= 0; --i) {
        if (allMessages[i].contentEquals(_lastProcessedMessage)) {
          foundIndex = i;
          break;
        }
      }
    }

    if (foundIndex < 0 || foundIndex + 1 < rawMessageCount) {
      groups.clear();
      _currentTurn = 0;
      appendFromMessages(allMessages, 0);
      return;
    }

    appendFromMessages(allMessages, foundIndex + 1);
  }

  void appendFromMessages(List<ChatMessage> messages, int startIndex) {
    var index = startIndex;

    while (index < messages.length) {
      final message = messages[index];

      if (message.role == ChatRole.system) {
        groups.add(
          createGroup(
            CompactionGroupKind.system,
            [message],
            tokenizer,
            turnIndex: null,
          ),
        );
        index++;
      } else if (message.role == ChatRole.user) {
        _currentTurn++;
        groups.add(
          createGroup(
            CompactionGroupKind.user,
            [message],
            tokenizer,
            turnIndex: _currentTurn,
          ),
        );
        index++;
      } else if (message.role == ChatRole.assistant && hasToolCalls(message)) {
        final groupMessages = <ChatMessage>[message];
        index++;
        while (index < messages.length &&
            (messages[index].role == ChatRole.tool ||
                (messages[index].role == ChatRole.assistant &&
                    hasOnlyReasoning(messages[index])))) {
          groupMessages.add(messages[index]);
          index++;
        }
        groups.add(
          createGroup(
            CompactionGroupKind.toolCall,
            groupMessages,
            tokenizer,
            turnIndex: _currentTurn,
          ),
        );
      } else if (message.role == ChatRole.assistant &&
          isSummaryMessage(message)) {
        groups.add(
          createGroup(
            CompactionGroupKind.summary,
            [message],
            tokenizer,
            turnIndex: _currentTurn,
          ),
        );
        index++;
      } else if (message.role == ChatRole.assistant &&
          hasOnlyReasoning(message)) {
        var lookahead = index + 1;
        while (lookahead < messages.length &&
            messages[lookahead].role == ChatRole.assistant &&
            hasOnlyReasoning(messages[lookahead])) {
          lookahead++;
        }

        if (lookahead < messages.length &&
            messages[lookahead].role == ChatRole.assistant &&
            hasToolCalls(messages[lookahead])) {
          final groupMessages = <ChatMessage>[
            for (var j = index; j <= lookahead; j++) messages[j],
          ];
          index = lookahead + 1;
          while (index < messages.length &&
              (messages[index].role == ChatRole.tool ||
                  (messages[index].role == ChatRole.assistant &&
                      hasOnlyReasoning(messages[index])))) {
            groupMessages.add(messages[index]);
            index++;
          }
          groups.add(
            createGroup(
              CompactionGroupKind.toolCall,
              groupMessages,
              tokenizer,
              turnIndex: _currentTurn,
            ),
          );
        } else {
          groups.add(
            createGroup(
              CompactionGroupKind.assistantText,
              [message],
              tokenizer,
              turnIndex: _currentTurn,
            ),
          );
          index++;
        }
      } else {
        groups.add(
          createGroup(
            CompactionGroupKind.assistantText,
            [message],
            tokenizer,
            turnIndex: _currentTurn,
          ),
        );
        index++;
      }
    }

    if (messages.isNotEmpty) {
      _lastProcessedMessage = messages.last;
    }
  }

  CompactionMessageGroup insertGroup(
    int index,
    CompactionGroupKind kind,
    List<ChatMessage> messages, {
    int? turnIndex,
  }) {
    final group = createGroup(kind, messages, tokenizer, turnIndex: turnIndex);
    groups.insert(index, group);
    return group;
  }

  CompactionMessageGroup addGroup(
    CompactionGroupKind kind,
    List<ChatMessage> messages, {
    int? turnIndex,
  }) {
    final group = createGroup(kind, messages, tokenizer, turnIndex: turnIndex);
    groups.add(group);
    return group;
  }

  Iterable<ChatMessage> getIncludedMessages() {
    return groups
        .where((group) => !group.isExcluded)
        .expand((group) => group.messages);
  }

  /// Total number of messages across all groups (included and excluded).
  int get totalMessageCount =>
      groups.fold(0, (sum, group) => sum + group.messageCount);

  /// Total byte count across all groups (included and excluded).
  int get totalByteCount =>
      groups.fold(0, (sum, group) => sum + group.byteCount);

  /// Total token count across all groups (included and excluded).
  int get totalTokenCount =>
      groups.fold(0, (sum, group) => sum + group.tokenCount);

  /// Total number of groups regardless of exclusion state.
  int get totalGroupCount => groups.length;

  /// Number of messages in non-excluded groups.
  int get includedMessageCount => groups
      .where((group) => !group.isExcluded)
      .fold(0, (sum, group) => sum + group.messageCount);

  /// Total byte count across non-excluded groups.
  int get includedByteCount => groups
      .where((group) => !group.isExcluded)
      .fold(0, (sum, group) => sum + group.byteCount);

  /// Total token count across non-excluded groups.
  int get includedTokenCount => groups
      .where((group) => !group.isExcluded)
      .fold(0, (sum, group) => sum + group.tokenCount);

  /// Number of non-excluded groups.
  int get includedGroupCount =>
      groups.where((group) => !group.isExcluded).length;

  /// Number of non-excluded, non-system groups.
  int get includedNonSystemGroupCount => groups
      .where(
        (group) =>
            !group.isExcluded && group.kind != CompactionGroupKind.system,
      )
      .length;

  /// Number of distinct conversation turns in non-excluded, non-system groups.
  int get includedTurnCount => groups
      .where(
        (group) =>
            !group.isExcluded &&
            group.kind != CompactionGroupKind.system &&
            group.turnIndex != null,
      )
      .map((group) => group.turnIndex)
      .toSet()
      .length;

  /// Total message count across all non-summary groups.
  int get rawMessageCount => groups
      .where((group) => group.kind != CompactionGroupKind.summary)
      .fold(0, (sum, group) => sum + group.messageCount);

  static bool hasToolCalls(ChatMessage message) {
    return message.contents.any((content) => content is FunctionCallContent);
  }

  static bool hasOnlyReasoning(ChatMessage message) {
    return message.contents.isNotEmpty &&
        message.contents.every((content) => content is TextReasoningContent);
  }

  static bool isSummaryMessage(ChatMessage message) {
    return message.additionalProperties?[CompactionMessageGroup
            .summaryPropertyKey] ==
        true;
  }

  static CompactionMessageGroup createGroup(
    CompactionGroupKind kind,
    List<ChatMessage> messages,
    Tokenizer? tokenizer, {
    int? turnIndex,
  }) {
    final byteCount = computeByteCount(messages);
    final tokenCount = tokenizer != null
        ? computeTokenCount(messages, tokenizer)
        : (byteCount / 4).ceil();

    return CompactionMessageGroup(
      kind,
      messages,
      byteCount,
      tokenCount,
      turnIndex: turnIndex,
    );
  }

  static int computeByteCount(List<ChatMessage> messages) {
    var total = 0;
    for (final message in messages) {
      total += getStringByteCount(message.authorName);
      for (final content in message.contents) {
        total += computeContentByteCount(content);
      }
    }
    return total;
  }

  static int computeTokenCount(
    List<ChatMessage> messages,
    Tokenizer tokenizer,
  ) {
    var total = 0;
    for (final message in messages) {
      if (message.authorName case final authorName?) {
        total += tokenizer.countTokens(authorName);
      }
      for (final content in message.contents) {
        switch (content) {
          case TextContent(:final text):
            total += tokenizer.countTokens(text);
          case TextReasoningContent(:final text, :final protectedData):
            total += tokenizer.countTokens(text);
            total += protectedData?.length ?? 0;
          case FunctionCallContent(:final name, :final arguments):
            total += tokenizer.countTokens(name);
            if (arguments != null) {
              for (final entry in arguments.entries) {
                total += tokenizer.countTokens(entry.key);
                total += tokenizer.countTokens(entry.value?.toString() ?? '');
              }
            }
          case FunctionResultContent(:final result):
            total += tokenizer.countTokens(result?.toString() ?? '');
          case DataContent(
            :final data,
            :final mediaType,
            :final name,
            :final uri,
          ):
            total += data?.length ?? 0;
            total += tokenizer.countTokens(mediaType ?? '');
            total += tokenizer.countTokens(name ?? '');
            total += tokenizer.countTokens(uri ?? '');
          case UriContent(:final uri, :final mediaType):
            total += tokenizer.countTokens(uri.toString());
            total += tokenizer.countTokens(mediaType);
          case ErrorContent(:final message, :final errorCode, :final details):
            total += tokenizer.countTokens(message);
            total += tokenizer.countTokens(errorCode ?? '');
            total += tokenizer.countTokens(details ?? '');
          case HostedFileContent(:final fileId, :final mediaType, :final name):
            total += tokenizer.countTokens(fileId);
            total += tokenizer.countTokens(mediaType ?? '');
            total += tokenizer.countTokens(name ?? '');
          default:
            total += tokenizer.countTokens(content.toString());
        }
      }
    }
    return total;
  }

  static int computeContentByteCount(AIContent content) {
    switch (content) {
      case TextContent(:final text):
        return getStringByteCount(text);
      case TextReasoningContent(:final text, :final protectedData):
        return getStringByteCount(text) + (protectedData?.length ?? 0);
      case FunctionCallContent(:final name, :final arguments):
        var count = getStringByteCount(name);
        if (arguments != null) {
          for (final entry in arguments.entries) {
            count += getStringByteCount(entry.key);
            count += getStringByteCount(entry.value?.toString());
          }
        }
        return count;
      case FunctionResultContent(:final result):
        return getStringByteCount(result?.toString());
      case DataContent(:final data, :final mediaType, :final name, :final uri):
        return (data?.length ?? 0) +
            getStringByteCount(mediaType) +
            getStringByteCount(name) +
            getStringByteCount(uri);
      case UriContent(:final uri, :final mediaType):
        return getStringByteCount(uri.toString()) +
            getStringByteCount(mediaType);
      case ErrorContent(:final message, :final errorCode, :final details):
        return getStringByteCount(message) +
            getStringByteCount(errorCode) +
            getStringByteCount(details);
      case HostedFileContent(:final fileId, :final mediaType, :final name):
        return getStringByteCount(fileId) +
            getStringByteCount(mediaType) +
            getStringByteCount(name);
      default:
        return getStringByteCount(content.toString());
    }
  }

  static int getStringByteCount(String? value) =>
      value == null || value.isEmpty ? 0 : utf8.encode(value).length;
}
