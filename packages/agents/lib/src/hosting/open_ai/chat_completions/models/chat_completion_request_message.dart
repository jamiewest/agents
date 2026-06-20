// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ChatCompletions/Models/ChatCompletionRequestMessage.cs.

import 'package:extensions/ai.dart';

import '../converters/message_content_part_converter.dart';
import 'message_content.dart';

/// A message in a chat completion request, discriminated by `role`.
abstract class ChatCompletionRequestMessage {
  /// Creates a [ChatCompletionRequestMessage] with the given [content].
  const ChatCompletionRequestMessage({required this.content});

  /// Parses a request message from JSON, dispatching on the `role` field.
  factory ChatCompletionRequestMessage.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String?;
    final content = MessageContent.fromJson(json['content']);
    final name = json['name'] as String?;
    switch (role) {
      case 'developer':
        return DeveloperMessage(content: content, name: name);
      case 'system':
        return SystemMessage(content: content, name: name);
      case 'user':
        return UserMessage(content: content, name: name);
      case 'assistant':
        return AssistantMessage(content: content, name: name);
      case 'tool':
        return ToolMessage(
          content: content,
          toolCallId: json['tool_call_id'] as String,
        );
      case 'function':
        return FunctionMessage(content: content, name: name ?? '');
      default:
        throw FormatException('Unknown message role: $role');
    }
  }

  /// The role of the message author.
  String get role;

  /// The contents of the message.
  final MessageContent content;

  /// Converts this request message to a [ChatMessage].
  ChatMessage toChatMessage() {
    final chatRole = ChatRole(role);
    if (content.isText) {
      return ChatMessage.fromText(chatRole, content.text!);
    }
    if (content.isContents) {
      final aiContents = content.contents!
          .map(MessageContentPartConverter.toAIContent)
          .whereType<AIContent>()
          .toList();
      return ChatMessage(role: chatRole, contents: aiContents);
    }
    throw StateError('MessageContent has no value');
  }
}

/// A developer message, providing system-level instructions.
class DeveloperMessage extends ChatCompletionRequestMessage {
  /// Creates a [DeveloperMessage].
  const DeveloperMessage({required super.content, this.name});

  /// An optional name for the participant.
  final String? name;

  @override
  String get role => 'developer';
}

/// A system message providing high-level instructions.
class SystemMessage extends ChatCompletionRequestMessage {
  /// Creates a [SystemMessage].
  const SystemMessage({required super.content, this.name});

  /// An optional name for the participant.
  final String? name;

  @override
  String get role => 'system';
}

/// A user message representing end-user input.
class UserMessage extends ChatCompletionRequestMessage {
  /// Creates a [UserMessage].
  const UserMessage({required super.content, this.name});

  /// An optional name for the participant.
  final String? name;

  @override
  String get role => 'user';
}

/// An assistant message representing a previous model response.
class AssistantMessage extends ChatCompletionRequestMessage {
  /// Creates an [AssistantMessage].
  const AssistantMessage({required super.content, this.name});

  /// An optional name for the participant.
  final String? name;

  @override
  String get role => 'assistant';
}

/// A tool message containing the result of a tool call.
class ToolMessage extends ChatCompletionRequestMessage {
  /// Creates a [ToolMessage].
  const ToolMessage({required super.content, required this.toolCallId});

  /// The tool call this message is responding to.
  final String toolCallId;

  @override
  String get role => 'tool';
}

/// A deprecated function message (replaced by tool messages).
class FunctionMessage extends ChatCompletionRequestMessage {
  /// Creates a [FunctionMessage].
  const FunctionMessage({required super.content, required this.name});

  /// The name of the function to call.
  final String name;

  @override
  String get role => 'function';

  @override
  ChatMessage toChatMessage() {
    if (content.isText) {
      return ChatMessage.fromText(ChatRole(role), content.text!);
    }
    throw StateError('FunctionMessage content must be text');
  }
}
