// ignore_for_file: non_constant_identifier_names
import 'dart:convert';

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
  (bool, T?) tryGetValue<T>(String key, {Object? JsonSerializerOptions}) {
    final stateValue = _state[key];
    if (stateValue == null) return (false, null);
    return stateValue.tryReadDeserializedValue<T>(
        JsonSerializerOptions: JsonSerializerOptions);
  }

  /// Returns the value of type [T] for the given [key], or `null`.
  T? getValue<T>(String key, {Object? JsonSerializerOptions}) {
    final stateValue = _state[key];
    if (stateValue == null) return null;
    return stateValue.readDeserializedValue<T>(
        JsonSerializerOptions: JsonSerializerOptions);
  }

  /// Stores a value of type [T] under the given [key].
  void setValue<T>(String key, T? value, {Object? JsonSerializerOptions}) {
    _state.putIfAbsent(key, () => AgentSessionStateBagValue(value));
    _state[key]!.setDeserialized<T>(value, T, JsonSerializerOptions);
  }

  /// Removes the value for the given [key].
  ///
  /// Returns `true` if the key was present.
  bool tryRemoveValue(String key) => _state.remove(key) != null;

  /// Serializes the state bag to a JSON String.
  String serialize() {
    return jsonEncode(
      _state.map((k, v) => MapEntry(k, v.toJson())),
    );
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
