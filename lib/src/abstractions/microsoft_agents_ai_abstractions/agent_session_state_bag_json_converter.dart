import 'agent_session_state_bag.dart';

/// Provides JSON encode/decode helpers for [AgentSessionStateBag] that
/// delegate to [AgentSessionStateBag.serialize] and
/// [AgentSessionStateBag.deserialize].
class AgentSessionStateBagJsonConverter {
  AgentSessionStateBagJsonConverter._();

  /// Encodes [value] to a JSON String.
  static String encode(AgentSessionStateBag value) => value.serialize();

  /// Decodes a JSON String to an [AgentSessionStateBag].
  static AgentSessionStateBag decode(String? json) =>
      AgentSessionStateBag.deserialize(json);
}
