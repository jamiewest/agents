import 'package:extensions/ai.dart';

import 'agent_response_update.dart';

/// Represents the response to an [AIAgent] run request, containing messages
/// and metadata about the interaction.
class AgentResponse {
  /// Creates an [AgentResponse] from a [ChatResponse], a single [message],
  /// or an explicit [messages] list.
  AgentResponse({
    ChatMessage? message,
    ChatResponse? response,
    List<ChatMessage>? messages,
  }) {
    if (response != null) {
      _messages = List<ChatMessage>.of(response.messages);
      finishReason = response.finishReason;
      continuationToken = response.continuationToken;
      rawRepresentation = response;
    } else if (message != null) {
      _messages = [message];
    } else {
      _messages = messages;
    }
  }

  List<ChatMessage>? _messages;

  /// The response messages. Setting to `null` causes subsequent reads to
  /// return an empty list.
  List<ChatMessage> get messages => _messages ?? const [];
  set messages(List<ChatMessage> value) => _messages = value;

  /// The identifier of the agent that generated this response.
  String? agentId;

  /// A unique identifier for this specific response.
  String? responseId;

  /// A continuation token for polling a background response.
  ResponseContinuationToken? continuationToken;

  /// Timestamp indicating when this response was created.
  DateTime? createdAt;

  /// Reason the agent response finished.
  ChatFinishReason? finishReason;

  /// Resource usage information for generating this response.
  UsageDetails? usage;

  /// The raw underlying implementation Object, if any.
  Object? rawRepresentation;

  /// Additional provider-specific metadata.
  AdditionalPropertiesDictionary? additionalProperties;

  /// The concatenated text of all messages in this response.
  String get text => _messages?.map((m) => m.text).join() ?? '';

  @override
  String toString() => text;

  /// Converts this response to a list of [AgentResponseUpdate] instances.
  List<AgentResponseUpdate> toAgentResponseUpdates() {
    final msgs = _messages ?? const <ChatMessage>[];
    final updates = <AgentResponseUpdate>[];
    for (final msg in msgs) {
      updates.add(AgentResponseUpdate(
        role: msg.role,
        contents: msg.contents,
      ));
    }
    if (usage != null || additionalProperties != null) {
      updates.add(AgentResponseUpdate(
        contents: [if (usage != null) UsageContent(usage!)],
      ));
    }
    return updates;
  }
}
