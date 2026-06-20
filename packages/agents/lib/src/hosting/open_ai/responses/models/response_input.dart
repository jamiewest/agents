// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/Models/ResponseInput.cs and InputMessage.cs.

import 'package:extensions/ai.dart';

/// The input to a response request: either a plain string or a list of
/// [InputMessage]s.
class ResponseInput {
  const ResponseInput._(this.text, this.messages);

  /// Creates a [ResponseInput] from a text string.
  factory ResponseInput.fromText(String text) => ResponseInput._(text, null);

  /// Creates a [ResponseInput] from a list of messages.
  factory ResponseInput.fromMessages(List<InputMessage> messages) =>
      ResponseInput._(null, messages);

  /// Parses a [ResponseInput] from a decoded JSON value (string or array).
  factory ResponseInput.fromJson(Object? json) {
    if (json is String) {
      return ResponseInput.fromText(json);
    }
    if (json is List) {
      return ResponseInput.fromMessages(
        json
            .whereType<Map<String, dynamic>>()
            .map(InputMessage.fromJson)
            .toList(),
      );
    }
    throw const FormatException(
      'ResponseInput must be a string or an array of messages.',
    );
  }

  /// The text value, or null when this is a list of messages.
  final String? text;

  /// The messages, or null when this is a text value.
  final List<InputMessage>? messages;

  /// Whether this input is a text string.
  bool get isText => text != null;

  /// Whether this input is a list of messages.
  bool get isMessages => messages != null;

  /// Normalizes this input to a list of [InputMessage]s.
  List<InputMessage> getInputMessages() {
    if (text != null) {
      return [InputMessage(role: 'user', content: text)];
    }
    return messages ?? const [];
  }

  /// Serializes this input as a string or list of messages.
  Object toJson() {
    if (isText) {
      return text!;
    }
    if (isMessages) {
      return messages!.map((m) => m.toJson()).toList();
    }
    throw StateError('ResponseInput has no value');
  }
}

/// A single input message with a role and content (string or content parts).
class InputMessage {
  /// Creates an [InputMessage].
  const InputMessage({required this.role, required this.content});

  /// Parses an [InputMessage] from a decoded JSON object.
  factory InputMessage.fromJson(Map<String, dynamic> json) =>
      InputMessage(role: json['role'] as String, content: json['content']);

  /// The role of the message author.
  final String role;

  /// The content: a string, or a list of content-part maps.
  final Object? content;

  /// Converts this message to a [ChatMessage].
  ChatMessage toChatMessage() {
    final chatRole = ChatRole(role);
    final value = content;
    if (value is String) {
      return ChatMessage.fromText(chatRole, value);
    }
    if (value is List) {
      final contents = <AIContent>[];
      for (final part in value.whereType<Map<String, dynamic>>()) {
        final text = part['text'];
        if (text is String) {
          contents.add(TextContent(text));
        }
      }
      return ChatMessage(role: chatRole, contents: contents);
    }
    return ChatMessage(role: chatRole, contents: const []);
  }

  /// Serializes this message.
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}
