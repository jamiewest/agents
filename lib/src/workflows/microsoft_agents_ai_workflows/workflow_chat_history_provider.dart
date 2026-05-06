import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/chat_history_provider.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';
import '../../json_stubs.dart';

class WorkflowChatHistoryProvider extends ChatHistoryProvider {
  /// Initializes a new instance of the [WorkflowChatHistoryProvider] class.
  ///
  /// [JsonSerializerOptions] Optional JSON serializer options for serializing
  /// the state of this provider. This is valuable for cases like when the chat
  /// history contains custom [AIContent] types and source generated serializers
  /// are required, or Native AOT / Trimming is required.
  WorkflowChatHistoryProvider({JsonSerializerOptions? JsonSerializerOptions = null}) {
    this._sessionState = ProviderSessionState<StoreState>(
            (_) => storeState(),
            this.runtimeType.toString(),
            JsonSerializerOptions);
  }

  late final ProviderSessionState<StoreState> _sessionState;

  List<String>? _stateKeys;

  List<String> get stateKeys {
    return this._stateKeys ??= [this._sessionState.stateKey];
  }

  void addMessages(AgentSession session, Iterable<ChatMessage> messages, ) {
    this._sessionState.getOrInitializeState(session).messages.addAll(messages);
  }

  @override
  Future<Iterable<ChatMessage>> provideChatHistory(
    InvokingContext context,
    {CancellationToken? cancellationToken, }
  ) {
    return new(this._sessionState.getOrInitializeState(context.session).messages.asReadOnly());
  }

  @override
  Future storeChatHistory(InvokedContext context, {CancellationToken? cancellationToken, }) {
    var allNewMessages = context.requestMessages + context.responseMessages ?? [];
    this._sessionState.getOrInitializeState(context.session).messages.addAll(allNewMessages);
    return Future.value();
  }

  Iterable<ChatMessage> getFromBookmark(AgentSession session) {
    var state = this._sessionState.getOrInitializeState(session);
    for (var i = state.bookmark; i < state.messages.length; i++) {
      yield state.messages[i];
    }
  }

  Iterable<ChatMessage> getAllMessages(AgentSession session) {
    var state = this._sessionState.getOrInitializeState(session);
    return state.messages.asReadOnly();
  }

  void updateBookmark(AgentSession session) {
    var state = this._sessionState.getOrInitializeState(session);
    state.bookmark = state.messages.length;
  }
}
class StoreState {
  StoreState();

  int bookmark;

  List<ChatMessage> messages = [];

}
