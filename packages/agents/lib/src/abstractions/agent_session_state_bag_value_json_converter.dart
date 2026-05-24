import 'agent_session_state_bag_value.dart';

/// Provides JSON encode/decode helpers for [AgentSessionStateBagValue] that
/// delegate to [AgentSessionStateBagValue.toJson] and
/// [AgentSessionStateBagValue.fromJson].
class AgentSessionStateBagValueJsonConverter {
  AgentSessionStateBagValueJsonConverter._();

  /// Encodes [value] to a JSON-compatible Object.
  static Object? encode(AgentSessionStateBagValue value) => value.toJson();

  /// Decodes a JSON-compatible Object to an [AgentSessionStateBagValue].
  static AgentSessionStateBagValue decode(Object? json) =>
      AgentSessionStateBagValue.fromJson(json);
}
