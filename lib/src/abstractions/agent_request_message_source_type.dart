/// Represents the source of an agent request message.
///
/// Remarks: Input messages for a specific agent run can originate from
/// various sources. This type helps to identify whether a message came from
/// outside the agent pipeline, whether it was produced by middleware, or came
/// from chat history.
class AgentRequestMessageSourceType {
  /// Creates an [AgentRequestMessageSourceType] with the given [value].
  const AgentRequestMessageSourceType(this.value);

  /// The String value representing the source of the agent request message.
  final String value;

  /// The message came from outside the agent pipeline (e.g., user input).
  static const AgentRequestMessageSourceType externalValue =
      AgentRequestMessageSourceType('External');

  /// The message was produced by an AI context provider.
  static const AgentRequestMessageSourceType aiContextProvider =
      AgentRequestMessageSourceType('AIContextProvider');

  /// The message came from chat history.
  static const AgentRequestMessageSourceType chatHistory =
      AgentRequestMessageSourceType('ChatHistory');

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentRequestMessageSourceType && value == other.value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
