import 'dart:convert';

import '../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';

/// Provides a conversation session for use with [ChatClientAgent].
class ChatClientAgentSession extends AgentSession {
  ChatClientAgentSession({
    String? conversationId,
    AgentSessionStateBag? stateBag,
  }) : super(stateBag ?? AgentSessionStateBag(null)) {
    this.conversationId = conversationId;
  }

  /// Gets or sets the ID of the underlying service chat history.
  ///
  /// May be null when the agent stores messages via a [ChatHistoryProvider]
  /// rather than in the agent service, or when server-managed chat history
  /// has not yet been created.
  late String? conversationId;

  /// Creates a [ChatClientAgentSession] from previously serialized JSON state.
  static ChatClientAgentSession deserialize(
    String serializedState, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
  }) {
    final map = jsonDecode(serializedState) as Map<String, dynamic>;
    return ChatClientAgentSession(
      conversationId: map['conversationId'] as String?,
    );
  }

  /// Serializes this session to a JSON String.
  // ignore: non_constant_identifier_names
  String serialize({Object? JsonSerializerOptions}) =>
      jsonEncode({'conversationId': conversationId});

  String get debuggerDisplay => conversationId != null
      ? 'conversationId = $conversationId'
      : 'No conversation ID';
}
