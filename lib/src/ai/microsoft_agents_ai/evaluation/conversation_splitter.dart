/// Built-in conversation splitters for common evaluation patterns.
///
/// Remarks: [LastTurn]: Evaluates whether the agent answered the latest
/// question well. [Full]: Evaluates whether the whole conversation trajectory
/// served the original request. For custom splits, implement
/// [ConversationSplitter] directly.
class ConversationSplitters {
  ConversationSplitters();

  /// Split at the last user message. Everything up to and including that
  /// message is the query; everything after is the response. This is the
  /// default strategy.
  static final ConversationSplitter lastTurn = LastTurnSplitter();

  /// The first user message (and any preceding system messages) is the query;
  /// the entire remainder of the conversation is the response. Evaluates
  /// overall conversation trajectory.
  static final ConversationSplitter full = FullSplitter();
}

class FullSplitter implements ConversationSplitter {
  FullSplitter();

  @override
  (List<ChatMessage>, List<ChatMessage>) split(
    List<ChatMessage> conversation,
  ) {
    var firstUserIdx = -1;
    for (var i = 0; i < conversation.length; i++) {
      if (conversation[i].role == ChatRole.user) {
        firstUserIdx = i;
        break;
      }
    }
    if (firstUserIdx >= 0) {
      return (
        conversation.take(firstUserIdx + 1).toList(),
        conversation.skip(firstUserIdx + 1).toList(),
      );
    }
    return (List<ChatMessage>(), conversation.toList());
  }
}

class LastTurnSplitter implements ConversationSplitter {
  LastTurnSplitter();

  @override
  (List<ChatMessage>, List<ChatMessage>) split(
    List<ChatMessage> conversation,
  ) {
    var lastUserIdx = -1;
    for (var i = 0; i < conversation.length; i++) {
      if (conversation[i].role == ChatRole.user) {
        lastUserIdx = i;
      }
    }
    if (lastUserIdx >= 0) {
      return (
        conversation.take(lastUserIdx + 1).toList(),
        conversation.skip(lastUserIdx + 1).toList(),
      );
    }
    return (List<ChatMessage>(), conversation.toList());
  }
}

/// Strategy for splitting a conversation into query and response halves for
/// evaluation.
///
/// Remarks: Use one of the built-in splitters from [ConversationSplitters] or
/// implement your own for domain-specific splitting logic (e.g., splitting
/// before a memory-retrieval tool call to evaluate recall quality).
abstract class ConversationSplitter {
  /// Splits a conversation into query messages and response messages.
  ///
  /// Returns: A tuple of (query messages, response messages).
  ///
  /// [conversation] The full conversation to split.
  (List<ChatMessage>, List<ChatMessage>)
  split(List<ChatMessage> conversation);
}
