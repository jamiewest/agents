// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Microsoft.Agents.AI.OpenAI/Extensions/OpenAIChatClientExtensions.cs.

import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';

import '../chat_client/chat_client_agent.dart';
import '../chat_client/chat_client_agent_options.dart';

/// Convenience methods for creating [ChatClientAgent] instances backed by
/// [OpenAIChatClient].
extension OpenAIChatClientAgentExtensions on OpenAIChatClient {
  /// Creates a [ChatClientAgent] backed by this OpenAI chat-completions client.
  ///
  /// If [options] is supplied it is used directly and the convenience
  /// parameters are ignored, matching the overload split in the upstream C#
  /// API. [chatClientFactory] can wrap the OpenAI [ChatClient] before the agent
  /// is created.
  ChatClientAgent asAIAgent({
    ChatClientAgentOptions? options,
    String? instructions,
    String? name,
    String? description,
    List<AITool>? tools,
    ChatClient Function(ChatClient chatClient)? chatClientFactory,
    LoggerFactory? loggerFactory,
    Object? services,
  }) {
    final agentOptions =
        options ??
        (ChatClientAgentOptions()
          ..name = name
          ..description = description
          ..chatOptions = _buildChatOptions(instructions, tools));

    final chatClient = chatClientFactory == null
        ? this
        : chatClientFactory(this);
    return ChatClientAgent(
      chatClient,
      options: agentOptions,
      loggerFactory: loggerFactory,
      services: services,
    );
  }

  static ChatOptions? _buildChatOptions(
    String? instructions,
    List<AITool>? tools,
  ) {
    final hasInstructions =
        instructions != null && instructions.trim().isNotEmpty;
    final hasTools = tools != null && tools.isNotEmpty;
    if (!hasInstructions && !hasTools) {
      return null;
    }
    return ChatOptions(instructions: instructions, tools: tools);
  }
}
