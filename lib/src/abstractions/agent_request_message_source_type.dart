/// The source of an agent request message.
///
/// Input messages for a specific agent run can originate from various sources,
/// such as user input, AI context providers, or chat history.
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
