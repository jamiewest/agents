import 'package:extensions/ai.dart';
class MultiPartyConversation {
  MultiPartyConversation();

  final List<ChatMessage> _history = [];

  final Object _mutex;

  List<ChatMessage> cloneAllMessages() {
    /* TODO: unsupported node kind "unknown" */
    // lock (this._mutex)
    //         {
    //             return this._history.ToList();
    //         }
  }
  (ChatMessage, int) collectNewMessages(int bookmark) {
    /* TODO: unsupported node kind "unknown" */
    // lock (this._mutex)
    //         {
    //             int count = this._history.Count - bookmark;
    //             if (count < 0)
    //             {
    //                 throw new InvalidOperationException($"Bookmark value too large: {bookmark} vs count={count}");
    //             }
    //
    //             return (this._history.Skip(bookmark).ToArray(), this.CurrentBookmark);
    //         }
  }
  int get currentBookmark {
    return this._history.length;
  }

  int addMessages(Iterable<ChatMessage> messages) {
    /* TODO: unsupported node kind "unknown" */
    // lock (this._mutex)
    //         {
    //             this._history.AddRange(messages);
    //             return this.CurrentBookmark;
    //         }
  }
  int addMessage(ChatMessage message) {
    /* TODO: unsupported node kind "unknown" */
    // lock (this._mutex)
    //         {
    //             this._history.Add(message);
    //             return this.CurrentBookmark;
    //         }
  }
}
