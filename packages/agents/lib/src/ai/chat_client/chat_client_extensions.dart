import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';

import 'approval_not_required_function_bypassing_chat_client.dart';
import 'approval_response_binding_chat_client.dart';
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

    // Registration order matters: the first `use` is the outermost decorator.
    // Approval-response binding sits above approval-not-required bypassing so
    // it sees the caller's raw approval responses before any
    // framework-generated ones are injected below it.
    if (options?.disableApprovalResponseBinding != true) {
      chatBuilder.use(
        (innerClient) => ApprovalResponseBindingChatClient(
          innerClient,
          loggerFactory: loggerFactory,
        ),
      );
    }

    if (options?.disableApprovalNotRequiredFunctionBypassing != true) {
      chatBuilder.use(
        (innerClient) => ApprovalNotRequiredFunctionBypassingChatClient(
          innerClient,
          loggerFactory: loggerFactory,
        ),
      );
    }

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
