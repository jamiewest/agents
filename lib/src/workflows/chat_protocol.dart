import 'package:extensions/ai.dart';

import '../abstractions/agent_response.dart';
import '../abstractions/agent_response_update.dart';
import 'protocol_builder.dart';

/// Describes the chat message protocol used by agent workflow executors.
class ChatProtocol {
  const ChatProtocol._();

  /// Configures an executor to accept common chat input shapes.
  static void configureInput(ProtocolBuilder builder) {
    builder
        .acceptsMessage<String>()
        .acceptsMessage<ChatMessage>()
        .acceptsMessage<List<ChatMessage>>();
  }

  /// Configures an executor to produce agent responses.
  static void configureOutput(ProtocolBuilder builder) {
    builder
        .sendsMessage<AgentResponse>()
        .sendsMessage<AgentResponseUpdate>()
        .sendsMessage<ChatMessage>();
  }

  /// Converts workflow input into chat messages.
  ///
  /// [stringRole] controls the [ChatRole] assigned to bare [String] inputs;
  /// defaults to [ChatRole.user].
  static List<ChatMessage> toChatMessages(
    Object? input, {
    ChatRole stringRole = ChatRole.user,
  }) {
    if (input == null) {
      return const <ChatMessage>[];
    }
    if (input is String) {
      return <ChatMessage>[ChatMessage.fromText(stringRole, input)];
    }
    if (input is ChatMessage) {
      return <ChatMessage>[input];
    }
    if (input is AgentResponse) {
      return List<ChatMessage>.of(input.messages);
    }
    if (input is Iterable<ChatMessage>) {
      return List<ChatMessage>.of(input);
    }
    return <ChatMessage>[ChatMessage.fromText(ChatRole.user, input.toString())];
  }

  /// Converts an arbitrary workflow output into agent response messages.
  static List<ChatMessage> toResponseMessages(Object? output) {
    if (output == null) {
      return const <ChatMessage>[];
    }
    if (output is AgentResponse) {
      return List<ChatMessage>.of(output.messages);
    }
    if (output is ChatMessage) {
      return <ChatMessage>[output];
    }
    if (output is Iterable<ChatMessage>) {
      return List<ChatMessage>.of(output);
    }
    if (output is AgentResponseUpdate) {
      return <ChatMessage>[
        ChatMessage(
          role: output.role ?? ChatRole.assistant,
          contents: output.contents,
        ),
      ];
    }
    return <ChatMessage>[
      ChatMessage.fromText(ChatRole.assistant, output.toString()),
    ];
  }
}
