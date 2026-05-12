import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/chat_history_provider.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';

/// A [ChatHistoryProvider] that persists chat messages in the agent session
/// state bag and supports bookmark-based incremental retrieval.
///
/// Used internally by workflow executors to maintain per-session chat history.
class WorkflowChatHistoryProvider extends ChatHistoryProvider {
  /// Creates a [WorkflowChatHistoryProvider].
  WorkflowChatHistoryProvider()
      : _sessionState = ProviderSessionState<_StoreState>(
          (_) => _StoreState(),
          'WorkflowChatHistoryProvider',
        );

  final ProviderSessionState<_StoreState> _sessionState;
  List<String>? _stateKeys;

  @override
  List<String> get stateKeys => _stateKeys ??= [_sessionState.stateKey];

  /// Appends [messages] to the history stored for [session].
  void addMessages(AgentSession session, Iterable<ChatMessage> messages) {
    _sessionState.getOrInitializeState(session).messages.addAll(messages);
  }

  @override
  Future<Iterable<ChatMessage>> provideChatHistory(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    return List<ChatMessage>.unmodifiable(
      _sessionState.getOrInitializeState(context.session).messages,
    );
  }

  @override
  Future<void> storeChatHistory(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final state = _sessionState.getOrInitializeState(context.session);
    state.messages.addAll(context.requestMessages);
    state.messages.addAll(context.responseMessages ?? const []);
  }

  /// Returns messages stored after the last [updateBookmark] call for
  /// [session].
  Iterable<ChatMessage> getFromBookmark(AgentSession session) {
    final state = _sessionState.getOrInitializeState(session);
    return state.messages.skip(state.bookmark);
  }

  /// Returns all messages stored for [session].
  Iterable<ChatMessage> getAllMessages(AgentSession session) {
    return List<ChatMessage>.unmodifiable(
      _sessionState.getOrInitializeState(session).messages,
    );
  }

  /// Advances the bookmark to the current end of the message list for
  /// [session].
  void updateBookmark(AgentSession session) {
    final state = _sessionState.getOrInitializeState(session);
    state.bookmark = state.messages.length;
  }
}

class _StoreState {
  int bookmark = 0;
  List<ChatMessage> messages = [];
}
