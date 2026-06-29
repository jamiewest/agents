import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';

import '../ai/chat_client/chat_client_agent.dart';
import '../ai/chat_client/chat_client_agent_options.dart';
import 'anthropic_chat_client.dart';
import 'anthropic_defaults.dart';

/// Extension methods for creating chat clients and agents from Anthropic
/// clients.
extension AnthropicClientAgentExtensions on anthropic.AnthropicClient {
  /// Creates a [ChatClient] backed by this Anthropic client.
  ChatClient asChatClient({
    String? modelId,
    int? defaultMaxTokens,
    List<String> betas = const [],
  }) {
    return AnthropicChatClient(
      this,
      modelId: modelId,
      defaultMaxTokens: defaultMaxTokens ?? AnthropicDefaults.defaultMaxTokens,
      betas: betas,
    );
  }

  /// Creates an AI agent backed by Anthropic's Messages API.
  ChatClientAgent asAIAgent({
    String? modelId,
    ChatClientAgentOptions? options,
    String? instructions,
    String? name,
    String? description,
    List<AITool>? tools,
    int? defaultMaxTokens,
    List<String> betas = const [],
    ChatClient Function(ChatClient)? clientFactory,
    LoggerFactory? loggerFactory,
    Object? services,
  }) {
    var chatClient = asChatClient(
      modelId: modelId,
      defaultMaxTokens: defaultMaxTokens,
      betas: betas,
    );
    if (clientFactory != null) {
      chatClient = clientFactory(chatClient);
    }

    if (options != null) {
      return ChatClientAgent(
        chatClient,
        options: options,
        loggerFactory: loggerFactory,
        services: services,
      );
    }

    return ChatClientAgent.withSettings(
      chatClient,
      instructions: instructions,
      name: name,
      description: description,
      tools: tools,
      loggerFactory: loggerFactory,
      services: services,
    );
  }
}
