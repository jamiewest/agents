import 'chat_history_memory_provider.dart';

/// Allows scoping of chat history for the [ChatHistoryMemoryProvider].
class ChatHistoryMemoryProviderScope {
  /// Initializes a new instance of the [ChatHistoryMemoryProviderScope] class
  /// by cloning an existing scope.
  ///
  /// [sourceScope] The scope to clone.
  ChatHistoryMemoryProviderScope(ChatHistoryMemoryProviderScope sourceScope) {
    this.applicationId = sourceScope.applicationId;
    this.agentId = sourceScope.agentId;
    this.sessionId = sourceScope.sessionId;
    this.userId = sourceScope.userId;
  }

  /// Gets or sets an optional ID for the application to scope chat history to.
  ///
  /// Remarks: If not set, the scope of the chat history will span all
  /// applications.
  late String? applicationId;

  /// Gets or sets an optional ID for the agent to scope chat history to.
  ///
  /// Remarks: If not set, the scope of the chat history will span all agents.
  late String? agentId;

  /// Gets or sets an optional ID for the session to scope chat history to.
  late String? sessionId;

  /// Gets or sets an optional ID for the user to scope chat history to.
  ///
  /// Remarks: If not set, the scope of the chat history will span all users.
  late String? userId;
}
