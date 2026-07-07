import 'dart:convert';
import 'dart:developer' as developer;

import 'agent_session_state_bag_value.dart';

/// A key-value store for managing session-scoped state with type-safe access
/// and JSON serialization support.
class AgentSessionStateBag {
  AgentSessionStateBag(Map<String, AgentSessionStateBagValue>? state)
    : _state = state ?? {};

  final Map<String, AgentSessionStateBagValue> _state;

  /// The number of key-value pairs in the state bag.
  int get count => _state.length;

  /// Tries to get a value of type [T] for the given [key].
  ///
  /// Returns `(true, value)` if found and castable; `(false, null)` otherwise.
  (bool, T?) tryGetValue<T>(String key, {Object? jsonSerializerOptions}) {
    final stateValue = _state[key];
    if (stateValue == null) return (false, null);
    return stateValue.tryReadDeserializedValue<T>(
      jsonSerializerOptions: jsonSerializerOptions,
    );
  }

  /// Returns the value of type [T] for the given [key], or `null`.
  T? getValue<T>(String key, {Object? jsonSerializerOptions}) {
    final stateValue = _state[key];
    if (stateValue == null) return null;
    return stateValue.readDeserializedValue<T>(
      jsonSerializerOptions: jsonSerializerOptions,
    );
  }

  /// Stores a value of type [T] under the given [key].
  void setValue<T>(String key, T? value, {Object? jsonSerializerOptions}) {
    _state.putIfAbsent(key, () => AgentSessionStateBagValue(value));
    _state[key]!.setDeserialized<T>(value, T, jsonSerializerOptions);
  }

  /// Removes the value for the given [key].
  ///
  /// Returns `true` if the key was present.
  bool tryRemoveValue(String key) => _state.remove(key) != null;

  /// Serializes the state bag to a JSON String.
  ///
  /// Values that cannot be JSON-encoded (plain objects without a `toJson`)
  /// are skipped with a debug log. Upstream C# serializes every value via
  /// reflection-based `System.Text.Json`; Dart has no reflection, so values
  /// must be JSON-encodable (primitives, maps, lists, or objects exposing
  /// `toJson`) to round-trip.
  String serialize() {
    final encodable = <String, Object?>{};
    _state.forEach((key, value) {
      final raw = value.toJson();
      try {
        jsonEncode(raw);
        encodable[key] = raw;
      } on Object {
        developer.log(
          'Skipping non-JSON-encodable session state value for key "$key" '
          '(${raw.runtimeType}).',
          name: 'agents.abstractions.agent_session_state_bag',
        );
      }
    });
    return jsonEncode(encodable);
  }

  /// Deserializes an [AgentSessionStateBag] from a JSON String.
  static AgentSessionStateBag deserialize(String? json) {
    if (json == null || json.isEmpty) return AgentSessionStateBag(null);
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return AgentSessionStateBag(
        map.map((k, v) => MapEntry(k, AgentSessionStateBagValue.fromJson(v))),
      );
    } catch (_) {
      return AgentSessionStateBag(null);
    }
  }
}
