import 'chat_history_memory_provider.dart';

/// Allows scoping of chat history for the [ChatHistoryMemoryProvider].
class ChatHistoryMemoryProviderScope {
  ChatHistoryMemoryProviderScope({
    this.applicationId,
    this.agentId,
    this.sessionId,
    this.userId,
  });

  ChatHistoryMemoryProviderScope.clone(ChatHistoryMemoryProviderScope source)
    : applicationId = source.applicationId,
      agentId = source.agentId,
      sessionId = source.sessionId,
      userId = source.userId;

  /// Optional ID for the application to scope chat history to.
  String? applicationId;

  /// Optional ID for the agent to scope chat history to.
  String? agentId;

  /// Optional ID for the session to scope chat history to.
  String? sessionId;

  /// Optional ID for the user to scope chat history to.
  String? userId;
}
