import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';

import 'chat_client_agent.dart';
import 'chat_client_agent_options.dart';
import 'per_service_call_chat_history_persisting_chat_client.dart';

/// Provides extension methods for creating [ChatClientAgent] instances from
/// [ChatClient] pipelines.
extension ChatClientExtensions on ChatClient {
  ChatClientAgent asAIAgent({
    ChatClientAgentOptions? options,
    String? instructions,
    String? name,
    String? description,
    List<AITool>? tools,
    LoggerFactory? loggerFactory,
    Object? services,
  }) {
    if (options != null) {
      return ChatClientAgent(
        this,
        options: options,
        loggerFactory: loggerFactory,
        services: services,
      );
    }

    return ChatClientAgent.withSettings(
      this,
      instructions: instructions,
      name: name,
      description: description,
      tools: tools,
      loggerFactory: loggerFactory,
      services: services,
    );
  }

  ChatClient withDefaultAgentMiddleware({
    ChatClientAgentOptions? options,
    LoggerFactory? loggerFactory,
  }) {
    final chatBuilder = ChatClientBuilder(this);

    if (getService<FunctionInvokingChatClient>() == null) {
      chatBuilder.use(
        (innerClient) => FunctionInvokingChatClient(
          innerClient,
          logger: loggerFactory?.createLogger('FunctionInvokingChatClient'),
        ),
      );
    }

    if (options?.requirePerServiceCallChatHistoryPersistence == true) {
      chatBuilder.use(
        (innerClient) =>
            PerServiceCallChatHistoryPersistingChatClient(innerClient),
      );
    }

    final agentChatClient = chatBuilder.build();
    final tools = options?.chatOptions?.tools;
    if (tools != null && tools.isNotEmpty) {
      final functionService = agentChatClient
          .getService<FunctionInvokingChatClient>();
      functionService?.additionalTools = List<AITool>.of(tools);
    }

    return agentChatClient;
  }
}
