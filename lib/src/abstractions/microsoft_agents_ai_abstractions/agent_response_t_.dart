import 'dart:convert';

import 'agent_response.dart';

/// Represents a typed response from an [AIAgent] run, containing both the
/// standard [AgentResponse] data and a deserialized result of type [T].
class AgentResponseOf<T> extends AgentResponse {
  /// Creates an [AgentResponseOf] from an existing [response], storing a
  /// pre-deserialized [result].
  AgentResponseOf(AgentResponse response, this.result) {
    messages = response.messages;
    agentId = response.agentId;
    responseId = response.responseId;
    continuationToken = response.continuationToken;
    createdAt = response.createdAt;
    finishReason = response.finishReason;
    usage = response.usage;
    rawRepresentation = response.rawRepresentation;
    additionalProperties = response.additionalProperties;
  }

  /// The deserialized result value.
  final T result;

  /// Whether [result] was unwrapped from a top-level JSON object during
  /// deserialization. Set by [AgentResponseExtensions] when applicable.
  bool isWrappedInObject = false;

  /// Attempts to deserialize the first top-level JSON Object from [json] into
  /// type [T].
  static T? deserializeFirstTopLevelObject<T>(String json) {
    try {
      return jsonDecode(json) as T?;
    } catch (_) {
      return null;
    }
  }
}
