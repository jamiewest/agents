import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';

import '../ai/chat_client/chat_client_agent.dart';
import '../ai/chat_client/chat_client_agent_options.dart';
import 'gemini_chat_client.dart';
import 'gemini_client.dart';

/// Extension methods for creating chat clients and agents from Gemini clients.
extension GeminiClientAgentExtensions on GeminiClient {
  /// Creates a [ChatClient] backed by this Gemini client.
  ChatClient asChatClient({String? modelId}) {
    return GeminiChatClient(this, modelId: modelId);
  }

  /// Creates an AI agent backed by the Gemini API.
  ChatClientAgent asAIAgent({
    String? modelId,
    ChatClientAgentOptions? options,
    String? instructions,
    String? name,
    String? description,
    List<AITool>? tools,
    ChatClient Function(ChatClient)? clientFactory,
    LoggerFactory? loggerFactory,
    Object? services,
  }) {
    var chatClient = asChatClient(modelId: modelId);
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
