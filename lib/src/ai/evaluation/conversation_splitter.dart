import 'package:extensions/ai.dart';

/// Built-in conversation splitters for common evaluation patterns.
class ConversationSplitters {
  ConversationSplitters._();

  /// Split at the last user message.
  static final ConversationSplitter lastTurn = LastTurnSplitter();

  /// Split at the first user message.
  static final ConversationSplitter full = FullSplitter();
}

/// Splits a conversation at the first user message, returning everything
/// from the start through that message as the query half.
class FullSplitter implements ConversationSplitter {
  @override
  (List<ChatMessage>, List<ChatMessage>) split(List<ChatMessage> conversation) {
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
    return (<ChatMessage>[], conversation.toList());
  }
}

/// Splits a conversation at the last user message, returning everything
/// from the start through that message as the query half.
class LastTurnSplitter implements ConversationSplitter {
  @override
  (List<ChatMessage>, List<ChatMessage>) split(List<ChatMessage> conversation) {
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
    return (<ChatMessage>[], conversation.toList());
  }
}

/// Strategy for splitting a conversation into query and response halves for
/// evaluation.
abstract class ConversationSplitter {
  /// Splits a conversation into query messages and response messages.
  (List<ChatMessage>, List<ChatMessage>) split(List<ChatMessage> conversation);
}
