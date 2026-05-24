import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/logging.dart';

import 'chat_client_agent.dart';
import 'chat_client_agent_options.dart';
import 'chat_client_extensions.dart';
import 'per_service_call_chat_history_persisting_chat_client.dart';

/// Provides extension methods for building [ChatClientAgent] instances from
/// [ChatClientBuilder] pipelines.
extension ChatClientBuilderAgentExtensions on ChatClientBuilder {
  ChatClientAgent buildAIAgent({
    ChatClientAgentOptions? options,
    String? instructions,
    String? name,
    String? description,
    List<AITool>? tools,
    LoggerFactory? loggerFactory,
    ServiceProvider? services,
  }) {
    final chatClient = build(services);
    if (options != null) {
      return chatClient.asAIAgent(
        options: options,
        loggerFactory: loggerFactory,
        services: services,
      );
    }

    return chatClient.asAIAgent(
      instructions: instructions,
      name: name,
      description: description,
      tools: tools,
      loggerFactory: loggerFactory,
      services: services,
    );
  }

  ChatClientBuilder usePerServiceCallChatHistoryPersistence() {
    return use(
      (innerClient) =>
          PerServiceCallChatHistoryPersistingChatClient(innerClient),
    );
  }
}
