import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/logging.dart';

import 'approval_not_required_function_bypassing_chat_client.dart';
import 'approval_response_binding_chat_client.dart';
import 'chat_client_agent.dart';
import 'chat_client_agent_options.dart';
import 'chat_client_extensions.dart';
import 'message_injecting_chat_client.dart';
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

  /// Adds a [MessageInjectingChatClient] to the chat client pipeline.
  ///
  /// The client can be retrieved from the built chat client via
  /// `getService<MessageInjectingChatClient>()` to enqueue messages from
  /// tool delegates or other code.
  ChatClientBuilder useMessageInjection() {
    return use((innerClient) => MessageInjectingChatClient(innerClient));
  }

  /// Adds an [ApprovalNotRequiredFunctionBypassingChatClient] to the chat
  /// client pipeline. Place it above the `FunctionInvokingChatClient` so
  /// approval requests for tools that do not require approval are handled
  /// transparently.
  ///
  /// Only needed when building a custom chat client stack: the default agent
  /// pipeline adds it unless
  /// [ChatClientAgentOptions.disableApprovalNotRequiredFunctionBypassing] is
  /// `true`.
  ChatClientBuilder useApprovalNotRequiredFunctionBypassing({
    LoggerFactory? loggerFactory,
  }) {
    return use(
      (innerClient) => ApprovalNotRequiredFunctionBypassingChatClient(
        innerClient,
        loggerFactory: loggerFactory,
      ),
    );
  }

  /// Adds an [ApprovalResponseBindingChatClient] to the chat client pipeline.
  ///
  /// Place it above both [useApprovalNotRequiredFunctionBypassing] and the
  /// `FunctionInvokingChatClient`, so it inspects the caller's raw approval
  /// responses before any framework-generated ones are injected below it.
  ///
  /// Only needed when building a custom chat client stack: the default agent
  /// pipeline adds it unless
  /// [ChatClientAgentOptions.disableApprovalResponseBinding] is `true`.
  ChatClientBuilder useApprovalResponseBinding({LoggerFactory? loggerFactory}) {
    return use(
      (innerClient) => ApprovalResponseBindingChatClient(
        innerClient,
        loggerFactory: loggerFactory,
      ),
    );
  }
}
