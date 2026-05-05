import 'package:extensions/ai.dart';

import 'agent_request_message_source_attribution.dart';
import 'agent_request_message_source_type.dart';

/// Extension methods for [ChatMessage] related to agent request message
/// source attribution.
extension ChatMessageExtensions on ChatMessage {
  /// Returns the [AgentRequestMessageSourceType] for this message.
  ///
  /// Defaults to [AgentRequestMessageSourceType.externalValue] when no
  /// explicit source attribution is stored in [additionalProperties].
  AgentRequestMessageSourceType getAgentRequestMessageSourceType() {
    final attribution = _getAttribution();
    return attribution?.sourceType ??
        AgentRequestMessageSourceType.externalValue;
  }

  /// Returns the source identifier for this message, or `null` if none.
  String? getAgentRequestMessageSourceId() => _getAttribution()?.sourceId;

  /// Returns a copy of this message tagged with [sourceType] and [sourceId].
  ///
  /// If the message is already tagged with the same values it is returned
  /// unchanged; otherwise a new [ChatMessage] with updated
  /// [additionalProperties] is returned.
  ChatMessage withAgentRequestMessageSource(
    AgentRequestMessageSourceType sourceType, {
    String? sourceId,
  }) {
    final existing = _getAttribution();
    if (existing != null &&
        existing.sourceType == sourceType &&
        existing.sourceId == sourceId) {
      return this;
    }

    final newProps = AdditionalPropertiesDictionary.of(
      additionalProperties ?? const {},
    );
    newProps[AgentRequestMessageSourceAttribution.additionalPropertiesKey] =
        AgentRequestMessageSourceAttribution(sourceType, sourceId);

    return ChatMessage(role: role, contents: List.of(contents), additionalProperties: newProps);
  }

  AgentRequestMessageSourceAttribution? _getAttribution() {
    final v = additionalProperties?[
        AgentRequestMessageSourceAttribution.additionalPropertiesKey];
    return v is AgentRequestMessageSourceAttribution ? v : null;
  }
}
