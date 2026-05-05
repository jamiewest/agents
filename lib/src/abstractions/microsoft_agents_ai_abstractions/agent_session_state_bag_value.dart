import 'dart:convert';

/// Stores a single value in an [AgentSessionStateBag].
///
/// Values are held as deserialized objects and serialized to JSON on demand.
class AgentSessionStateBagValue {
  AgentSessionStateBagValue(this._value);

  Object? _value;

  /// Tries to read the stored value as type [T].
  ///
  /// Returns a `(found, value)` record. `found` is `false` if the stored
  /// value cannot be cast to [T].
  (bool, T?) tryReadDeserializedValue<T>({Object? JsonSerializerOptions}) {
    final v = _value;
    if (v == null) return (true, null);
    if (v is T) return (true, v as T);
    return (false, null);
  }

  /// Reads the stored value as type [T], throwing if the cast fails.
  T? readDeserializedValue<T>({Object? JsonSerializerOptions}) {
    final v = _value;
    if (v == null) return null;
    if (v is T) return v as T;
    throw StateError(
        'Session state value is ${v.runtimeType}, not $T.');
  }

  /// Replaces the stored value.
  void setDeserialized<T>(T? value, Type valueType,
      Object? JsonSerializerOptions) {
    _value = value;
  }

  /// Serializes the stored value to a JSON-compatible Object.
  Object? toJson() => _value;

  /// Creates an [AgentSessionStateBagValue] from a JSON-decoded value.
  static AgentSessionStateBagValue fromJson(Object? json) =>
      AgentSessionStateBagValue(json);
}
