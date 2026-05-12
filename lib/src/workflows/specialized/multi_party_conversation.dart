import 'package:extensions/ai.dart';

/// Stores the shared conversation history for a multi-party workflow.
class MultiPartyConversation {
  /// Creates a [MultiPartyConversation].
  MultiPartyConversation([
    Iterable<ChatMessage> history = const <ChatMessage>[],
  ]) : history = List<ChatMessage>.of(history);

  /// Gets the conversation history.
  final List<ChatMessage> history;

  /// Clones the current history.
  List<ChatMessage> cloneHistory() => List<ChatMessage>.of(history);

  /// Collects messages added since [bookmark].
  (List<ChatMessage>, int) collectNewMessages(int bookmark) {
    final count = history.length - bookmark;
    if (count < 0) {
      throw StateError('Bookmark value too large: $bookmark vs count=$count');
    }
    return (history.skip(bookmark).toList(), currentBookmark);
  }

  /// Gets the current bookmark.
  int get currentBookmark => history.length;

  /// Adds [messages] and returns the new bookmark.
  int addMessages(Iterable<ChatMessage> messages) {
    history.addAll(messages);
    return currentBookmark;
  }

  /// Adds [message] and returns the new bookmark.
  int addMessage(ChatMessage message) {
    history.add(message);
    return currentBookmark;
  }
}
