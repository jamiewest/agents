import 'package:extensions/logging.dart';

/// Logging extensions for [ChatClientAgent] invocations.
extension ChatClientAgentLogMessages on Logger {
  /// Logs that the [ChatClientAgent] is about to invoke the underlying client.
  void logAgentChatClientInvokingAgent(
    String methodName,
    String agentId,
    String agentName,
    Type clientType,
  ) {
    if (!isEnabled(LogLevel.debug)) return;
    logDebug(
      'ChatClientAgent invoking. Method: $methodName. '
      'AgentId: $agentId. AgentName: $agentName. Client: $clientType.',
    );
  }

  /// Logs that the [ChatClientAgent] has completed a non-streaming invocation.
  void logAgentChatClientInvokedAgent(
    String methodName,
    String agentId,
    String agentName,
    Type clientType,
    int messageCount,
  ) {
    if (!isEnabled(LogLevel.debug)) return;
    logDebug(
      'ChatClientAgent invoked. Method: $methodName. '
      'AgentId: $agentId. AgentName: $agentName. Client: $clientType. '
      'Messages: $messageCount.',
    );
  }

  /// Logs that the [ChatClientAgent] has completed a streaming invocation.
  void logAgentChatClientInvokedStreamingAgent(
    String methodName,
    String agentId,
    String agentName,
    Type clientType,
  ) {
    if (!isEnabled(LogLevel.debug)) return;
    logDebug(
      'ChatClientAgent invoked streaming. Method: $methodName. '
      'AgentId: $agentId. AgentName: $agentName. Client: $clientType.',
    );
  }

  /// Logs a warning when both a conversation id and a chat history provider
  /// are configured simultaneously.
  void logAgentChatClientHistoryProviderConflict(
    String conversationIdName,
    String chatHistoryProviderName,
    String agentId,
    String agentName,
  ) {
    logWarning(
      'ChatClientAgent history provider conflict: both $conversationIdName '
      'and $chatHistoryProviderName are set. '
      'AgentId: $agentId. AgentName: $agentName.',
    );
  }

  /// Logs a warning when per-service-call history persistence is required but
  /// no [PerServiceCallChatHistoryPersistingChatClient] is found in the
  /// pipeline.
  void logAgentChatClientMissingPersistingClient(
    String agentId,
    String agentName,
  ) {
    logWarning(
      'ChatClientAgent: RequirePerServiceCallChatHistoryPersistence is true '
      'but no PerServiceCallChatHistoryPersistingChatClient was found. '
      'AgentId: $agentId. AgentName: $agentName.',
    );
  }

  /// Logs a warning when per-service-call persistence falls back to
  /// end-of-run persistence because the run involves background responses.
  void logAgentChatClientBackgroundResponseFallback(
    String agentId,
    String agentName,
  ) {
    logWarning(
      'ChatClientAgent: per-service-call persistence is unreliable for '
      'background responses; falling back to end-of-run persistence. '
      'AgentId: $agentId. AgentName: $agentName.',
    );
  }
}
