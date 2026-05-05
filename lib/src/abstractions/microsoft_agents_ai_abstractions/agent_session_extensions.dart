import 'package:extensions/ai.dart';

import 'agent_session.dart';
import 'in_memory_chat_history_provider.dart';

/// Extension methods for [AgentSession].
extension AgentSessionExtensions on AgentSession {
  /// Attempts to retrieve the in-memory chat history messages for this session.
  ///
  /// Returns `(true, messages)` if found; `(false, null)` otherwise.
  ///
  /// Remarks: Only applicable when [InMemoryChatHistoryProvider] is in use.
  (bool, List<ChatMessage>?) tryGetInMemoryChatHistory({String? stateKey}) {
    final (found, state) = stateBag.tryGetValue<InMemoryChatHistoryProviderState>(
      stateKey ?? 'InMemoryChatHistoryProvider',
    );
    if (found && state != null) {
      return (true, state.messages);
    }
    return (false, null);
  }

  /// Sets the in-memory chat history for this session.
  ///
  /// Remarks: Only applicable when [InMemoryChatHistoryProvider] is in use.
  void setInMemoryChatHistory(
    List<ChatMessage> messages, {
    String? stateKey,
  }) {
    final key = stateKey ?? 'InMemoryChatHistoryProvider';
    final (found, state) = stateBag.tryGetValue<InMemoryChatHistoryProviderState>(key);
    if (found && state != null) {
      state.messages = messages;
    } else {
      stateBag.setValue<InMemoryChatHistoryProviderState>(
        key,
        InMemoryChatHistoryProviderState()..messages = messages,
      );
    }
  }
}
