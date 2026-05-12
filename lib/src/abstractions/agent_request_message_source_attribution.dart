import 'agent_request_message_source_type.dart';

/// Attribution information for the source of an agent request message,
/// including the component type and its identifier.
///
/// Use this to identify which component provided a message during an agent run
/// and to filter messages by source.
class AgentRequestMessageSourceAttribution {
  /// Creates an [AgentRequestMessageSourceAttribution] with the specified
  /// [sourceType] and optional [sourceId].
  const AgentRequestMessageSourceAttribution(this.sourceType, this.sourceId);

  /// The key used in additional properties to store source attribution.
  static const String additionalPropertiesKey = '_attribution';

  /// The type of component that provided the message.
  final AgentRequestMessageSourceType sourceType;

  /// The unique identifier of the component that provided the message.
  final String? sourceId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentRequestMessageSourceAttribution &&
        sourceType == other.sourceType &&
        sourceId == other.sourceId;
  }

  @override
  int get hashCode => Object.hash(sourceType, sourceId);

  @override
  String toString() =>
      sourceId == null ? '$sourceType' : '$sourceType:$sourceId';
}
