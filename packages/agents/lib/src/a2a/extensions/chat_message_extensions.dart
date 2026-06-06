import 'dart:math';

import 'package:a2a/a2a.dart';
import 'package:extensions/ai.dart';

import 'a2a_ai_content_extensions.dart';

/// Extension methods for converting [ChatMessage] collections to an
/// [A2AMessage].
extension ChatMessageA2AExtensions on Iterable<ChatMessage> {
  /// Merges all messages into a single outbound [A2AMessage].
  ///
  /// Parts from every message are collected in order. The resulting message
  /// has role `'user'` and a freshly generated UUID message identifier.
  A2AMessage toA2AMessage() {
    final allParts = <A2APart>[];
    for (final message in this) {
      final parts = message.contents.toParts();
      if (parts != null) allParts.addAll(parts);
    }
    return A2AMessage()
      ..messageId = _generateUuid()
      ..role = 'user'
      ..parts = allParts;
  }
}

/// Extension methods for converting an [A2AMessage] to a [ChatMessage].
extension A2AMessageExtensions on A2AMessage {
  /// Converts this [A2AMessage] to a [ChatMessage].
  ChatMessage toChatMessage() {
    final role = this.role == 'user' ? ChatRole.user : ChatRole.assistant;
    return ChatMessage(
      role: role,
      contents: (parts ?? []).map((p) => p.toAIContent()).toList(),
    )..rawRepresentation = this;
  }
}

final _random = Random.secure();

String _generateUuid() {
  final rand = List<int>.generate(16, (_) => _random.nextInt(256));
  rand[6] = (rand[6] & 0x0f) | 0x40;
  rand[8] = (rand[8] & 0x3f) | 0x80;
  String hex(int n) => n.toRadixString(16).padLeft(2, '0');
  final b = rand.map(hex).toList();
  return '${b[0]}${b[1]}${b[2]}${b[3]}-'
      '${b[4]}${b[5]}-'
      '${b[6]}${b[7]}-'
      '${b[8]}${b[9]}-'
      '${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
}
