import 'package:extensions/ai.dart';

/// Concatenates [ChatMessage.text] values across a list of messages.
extension ChatMessageListTextExtensions on List<ChatMessage> {
  /// Concatenates [ChatMessage.text] for every message, separated by
  /// newlines. Empty text values are skipped.
  String concatText() {
    if (isEmpty) return '';
    if (length == 1) return first.text;
    final buffer = StringBuffer();
    for (final message in this) {
      final text = message.text;
      if (text.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(text);
      }
    }
    return buffer.toString();
  }
}
