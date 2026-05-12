import 'checkpointing/delayed_deserialization.dart';
import 'checkpointing/json_wire_serialized_value.dart';
import 'checkpointing/type_id.dart';

/// Wraps an arbitrary value alongside its [TypeId], supporting optional
/// lazy deserialization via [IDelayedDeserialization].
class PortableValue {
  /// Creates a [PortableValue] wrapping [value].
  ///
  /// The [typeId] is derived from [value]'s runtime type.
  PortableValue(Object value)
      : typeId = TypeId.fromType(value.runtimeType),
        _value = value;

  /// Creates a [PortableValue] with an explicit [typeId].
  PortableValue.withTypeId(this.typeId, Object value) : _value = value;

  /// The type identifier of the wrapped value.
  final TypeId typeId;

  final Object _value;
  Object? _deserializedValueCache;

  /// Returns the value cast to [T], or `null` if the cast fails.
  ///
  /// If the underlying value implements [IDelayedDeserialization] and no
  /// cached result exists, it is deserialized and cached for future calls.
  T? asValue<T>() {
    final v = _value;
    if (v is T) return v as T;
    final cached = _deserializedValueCache;
    if (cached != null) {
      if (cached is T) return cached as T;
      return null;
    }
    if (v is IDelayedDeserialization) {
      final T result = v.deserialize<T>();
      _deserializedValueCache = result;
      return result;
    }
    return null;
  }

  /// Returns `true` if the value can be represented as [T].
  bool isValue<T>() => asValue<T>() != null;

  /// Returns the value if its runtime type is exactly [targetType],
  /// or deserializes it via [IDelayedDeserialization] when available.
  ///
  /// Returns `null` when the type does not match. Uses exact runtime-type
  /// matching; use [asValue] for polymorphic checks.
  Object? asType(Type targetType) {
    if (_value.runtimeType == targetType) return _value;
    final cached = _deserializedValueCache;
    if (cached != null) {
      return cached.runtimeType == targetType ? cached : null;
    }
    if (_value is IDelayedDeserialization) {
      final result = _value.deserializeAs(targetType);
      _deserializedValueCache = result;
      return result;
    }
    return null;
  }

  /// Returns `true` if the value can be represented as [targetType].
  bool isType(Type targetType) => asType(targetType) != null;

  /// Returns `true` if the underlying value supports lazy deserialization.
  bool get isDelayedDeserialization => _value is IDelayedDeserialization;

  /// Returns `true` if a deserialized value has been cached.
  bool get isDeserialized => _deserializedValueCache != null;

  /// Converts this value to a JSON-compatible map.
  ///
  /// If the underlying value is a [JsonWireSerializedValue] and has not been
  /// deserialized, its raw JSON content is preserved. Otherwise the stored
  /// value is used directly.
  Map<String, Object?> toJson() {
    Object? serialized;
    final v = _value;
    if (v is JsonWireSerializedValue) {
      serialized = v.value;
    } else {
      serialized = _deserializedValueCache ?? v;
    }
    return <String, Object?>{'typeId': typeId.value, 'value': serialized};
  }

  /// Creates a [PortableValue] from a JSON-compatible map.
  ///
  /// The raw JSON value is wrapped in a [JsonWireSerializedValue] to support
  /// lazy deserialization via [asValue] when the target type is known.
  factory PortableValue.fromJson(Map<String, Object?> json) {
    final typeIdStr = json['typeId'] as String? ?? '';
    final rawValue = json['value'];
    return PortableValue.withTypeId(
      TypeId(typeIdStr),
      JsonWireSerializedValue(value: rawValue, typeId: typeIdStr),
    );
  }
}
