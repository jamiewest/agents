import 'package:extensions/ai.dart';

import '../../abstractions/ai_context_provider.dart';
import '../../abstractions/chat_history_provider.dart';

/// Configuration options for a [ChatClientAgent].
class ChatClientAgentOptions {
  ChatClientAgentOptions();

  /// Optional agent identifier.
  String? id;

  /// Optional agent display name.
  String? name;

  /// Optional agent description.
  String? description;

  /// Default [ChatOptions] for every invocation.
  ChatOptions? chatOptions;

  /// Provider that loads and persists chat history for this agent.
  ChatHistoryProvider? chatHistoryProvider;

  /// Providers that inject additional context into each agent run.
  Iterable<AIContextProvider>? aiContextProviders;

  /// When `true`, the supplied [ChatClient] is used as-is without applying
  /// default decorators such as automatic function invocation.
  bool useProvidedChatClientAsIs = false;

  /// Whether functions may be invoked concurrently when a model response
  /// contains multiple function calls.
  ///
  /// This setting is independent of [ChatOptions.allowMultipleToolCalls],
  /// which controls whether a model may return multiple tool calls in a
  /// single response. The default is `false`. This option has no effect when
  /// [useProvidedChatClientAsIs] is `true`; when using a custom chat client
  /// stack, configure [FunctionInvokingChatClient.allowConcurrentInvocation]
  /// directly on its [FunctionInvokingChatClient] instance.
  bool allowConcurrentInvocation = false;

  /// When `true`, clears the [ChatHistoryProvider] if the AI service returns a
  /// conversation id (indicating service-managed history).
  bool clearOnChatHistoryProviderConflict = true;

  /// When `true`, logs a warning when both a conversation id and a
  /// [ChatHistoryProvider] are present.
  bool warnOnChatHistoryProviderConflict = true;

  /// When `true`, throws if both a conversation id and a [ChatHistoryProvider]
  /// are present simultaneously.
  bool throwOnChatHistoryProviderConflict = true;

  /// When `true`, history is persisted after each individual service call
  /// rather than at the end of the full agent run.
  bool requirePerServiceCallChatHistoryPersistence = false;

  /// When `true`, a `MessageInjectingChatClient` is added to the pipeline
  /// between the `FunctionInvokingChatClient` and the inner client. This
  /// enables external code (such as tool delegates) to inject messages into
  /// the function execution loop via the `MessageInjectingChatClient`, which
  /// can be resolved from the chat client using
  /// `getService<MessageInjectingChatClient>()`.
  ///
  /// It is recommended to also enable
  /// [requirePerServiceCallChatHistoryPersistence] when using message
  /// injection so injected messages are persisted between service calls.
  /// This option has no effect when [useProvidedChatClientAsIs] is `true`;
  /// add the decorator manually via `useMessageInjection` in that case.
  bool enableMessageInjection = false;

  /// When `false` (the default), an
  /// `ApprovalNotRequiredFunctionBypassingChatClient` decorator is injected
  /// above `FunctionInvokingChatClient` in the pipeline. The decorator
  /// identifies approval requests for tools that do not require approval,
  /// removes them from the response, and stores them in the session. On the
  /// next request the stored items are re-injected as approved, so the caller
  /// only needs to handle approval requests for tools that truly require
  /// human approval.
  ///
  /// Set to `true` to leave the decorator out of the pipeline.
  ///
  /// This option has no effect when [useProvidedChatClientAsIs] is `true`;
  /// add the decorator manually via
  /// `useApprovalNotRequiredFunctionBypassing` in that case.
  bool disableApprovalNotRequiredFunctionBypassing = false;

  /// When `false` (the default), an `ApprovalResponseBindingChatClient` is
  /// injected as the outermost agent decorator. It binds each inbound
  /// approval response to the model-originated approval request the framework
  /// surfaced, so an approved tool call always matches what was surfaced for
  /// approval, and drops responses that have no matching request.
  ///
  /// Set to `true` to leave the decorator out of the pipeline.
  ///
  /// This option has no effect when [useProvidedChatClientAsIs] is `true`;
  /// add the decorator manually via `useApprovalResponseBinding` in that
  /// case.
  bool disableApprovalResponseBinding = false;

  /// Creates a shallow copy of these options.
  ChatClientAgentOptions clone() => ChatClientAgentOptions()
    ..id = id
    ..name = name
    ..description = description
    ..chatOptions = chatOptions?.clone()
    ..chatHistoryProvider = chatHistoryProvider
    ..aiContextProviders = aiContextProviders == null
        ? null
        : List.of(aiContextProviders!)
    ..useProvidedChatClientAsIs = useProvidedChatClientAsIs
    ..allowConcurrentInvocation = allowConcurrentInvocation
    ..clearOnChatHistoryProviderConflict = clearOnChatHistoryProviderConflict
    ..warnOnChatHistoryProviderConflict = warnOnChatHistoryProviderConflict
    ..throwOnChatHistoryProviderConflict = throwOnChatHistoryProviderConflict
    ..requirePerServiceCallChatHistoryPersistence =
        requirePerServiceCallChatHistoryPersistence
    ..enableMessageInjection = enableMessageInjection
    ..disableApprovalNotRequiredFunctionBypassing =
        disableApprovalNotRequiredFunctionBypassing
    ..disableApprovalResponseBinding = disableApprovalResponseBinding;
}
