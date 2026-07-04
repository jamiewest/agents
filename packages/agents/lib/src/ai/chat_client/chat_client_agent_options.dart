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

  /// When `true`, a `NonApprovalRequiredFunctionBypassingChatClient`
  /// decorator is injected above `FunctionInvokingChatClient` in the
  /// pipeline. The decorator identifies approval requests for
  /// non-approval-required tools, removes them from the response, and stores
  /// them in the session. On the next request, the stored items are
  /// automatically re-injected as approved, so the caller only needs to
  /// handle approval requests for tools that truly require human approval.
  ///
  /// This option has no effect when [useProvidedChatClientAsIs] is `true`;
  /// add the decorator manually via
  /// `useNonApprovalRequiredFunctionBypassing` in that case.
  bool enableNonApprovalRequiredFunctionBypassing = false;

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
    ..clearOnChatHistoryProviderConflict = clearOnChatHistoryProviderConflict
    ..warnOnChatHistoryProviderConflict = warnOnChatHistoryProviderConflict
    ..throwOnChatHistoryProviderConflict = throwOnChatHistoryProviderConflict
    ..requirePerServiceCallChatHistoryPersistence =
        requirePerServiceCallChatHistoryPersistence
    ..enableMessageInjection = enableMessageInjection
    ..enableNonApprovalRequiredFunctionBypassing =
        enableNonApprovalRequiredFunctionBypassing;
}
