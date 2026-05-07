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

  /// Gets or sets an optional ID for the application to scope chat history to.
  String? applicationId;

  /// Gets or sets an optional ID for the agent to scope chat history to.
  String? agentId;

  /// Gets or sets an optional ID for the session to scope chat history to.
  String? sessionId;

  /// Gets or sets an optional ID for the user to scope chat history to.
  String? userId;
}
