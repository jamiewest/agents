import 'package:extensions/ai.dart';
/// Content-based equality comparison for [ChatMessage] instances.
extension ChatMessageContentEquality on ChatMessage? {
  /// Determines whether two [ChatMessage] instances represent the same message
  /// by content.
  ///
  /// Remarks: When both messages define a [MessageId], identity is determined
  /// solely by that identifier. Otherwise, the comparison falls through to
  /// [Role], [AuthorName], and each item in [Contents].
  bool contentEquals(ChatMessage? other) {
    if (identical(message, other)) {
      return true;
    }
    if (message == null || other == null) {
      return false;
    }
    if (message.messageId != null && other.messageId != null) {
      return (message.messageId == other.messageId,
        ,);
    }
    if (message.role != other.role) {
      return false;
    }
    if (!(message.authorName == other.authorName,
      ,)) {
      return false;
    }
    return contentsEqual(message.contents, other.contents);
  }
}
