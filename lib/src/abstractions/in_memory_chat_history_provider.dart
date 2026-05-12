import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'agent_session.dart';
import 'chat_history_provider.dart';
import 'in_memory_chat_history_provider_options.dart';
import 'provider_session_state_t_state_.dart';

/// In-memory implementation of [ChatHistoryProvider] with optional message
/// reduction support.
///
/// Stores chat messages in the session [AgentSessionStateBag]. For
/// long-running conversations or high-volume scenarios, consider message
/// reduction strategies via [InMemoryChatHistoryProviderOptions].
class InMemoryChatHistoryProvider extends ChatHistoryProvider {
  /// Creates an [InMemoryChatHistoryProvider] with optional [options].
  InMemoryChatHistoryProvider({InMemoryChatHistoryProviderOptions? options})
      : _sessionState = ProviderSessionState<InMemoryChatHistoryProviderState>(
          options?.stateInitializer ?? ((_) => InMemoryChatHistoryProviderState()),
          options?.stateKey ?? 'InMemoryChatHistoryProvider',
          JsonSerializerOptions: options?.JsonSerializerOptions,
        ),
        chatReducer = options?.chatReducer,
        reducerTriggerEvent =
            options?.reducerTriggerEvent ??
            ChatReducerTriggerEvent.beforeMessagesRetrieval,
        super(
          storeInputRequestMessageFilter: options?.storageInputRequestMessageFilter,
          storeInputResponseMessageFilter: options?.storageInputResponseMessageFilter,
          provideOutputMessageFilter: options?.provideOutputMessageFilter,
        );

  final ProviderSessionState<InMemoryChatHistoryProviderState> _sessionState;

  /// The chat reducer applied to messages, or `null` for no reduction.
  final ChatReducer? chatReducer;

  /// The event that triggers reducer invocation.
  final ChatReducerTriggerEvent reducerTriggerEvent;

  @override
  List<String> get stateKeys => [_sessionState.stateKey];

  /// Returns the chat messages stored for the given [session].
  List<ChatMessage> getMessages(AgentSession? session) {
    return _sessionState.getOrInitializeState(session).messages;
  }

  /// Replaces the chat messages for the given [session].
  void setMessages(AgentSession? session, List<ChatMessage> messages) {
    _sessionState.getOrInitializeState(session).messages = messages;
  }

  @override
  Future<Iterable<ChatMessage>> provideChatHistory(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final state = _sessionState.getOrInitializeState(context.session);
    if (reducerTriggerEvent == ChatReducerTriggerEvent.beforeMessagesRetrieval &&
        chatReducer != null) {
      await _reduceMessages(chatReducer!, state);
    }
    return state.messages;
  }

  @override
  Future<void> storeChatHistory(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final state = _sessionState.getOrInitializeState(context.session);
    final allNewMessages = [
      ...context.requestMessages,
      ...?context.responseMessages,
    ];
    state.messages.addAll(allNewMessages);
    if (reducerTriggerEvent == ChatReducerTriggerEvent.afterMessageAdded &&
        chatReducer != null) {
      await _reduceMessages(chatReducer!, state);
    }
  }

  static Future<void> _reduceMessages(
    ChatReducer reducer,
    InMemoryChatHistoryProviderState state,
  ) async {
    state.messages = await reducer.reduce(state.messages);
  }
}

/// The persisted state for [InMemoryChatHistoryProvider].
class InMemoryChatHistoryProviderState {
  /// The stored chat messages.
  List<ChatMessage> messages = [];
}
