import 'delayed_deserialization.dart';

/// Stores a JSON-shaped value together with optional type metadata,
/// supporting lazy deserialization when the target type is determined later.
class JsonWireSerializedValue implements IDelayedDeserialization {
  /// Creates a JSON wire serialized value.
  const JsonWireSerializedValue({required this.value, this.typeId});

  /// Gets the serialized JSON-shaped value.
  final Object? value;

  /// Gets the optional type identifier.
  final String? typeId;

  @override
  T deserialize<T>() {
    final v = value;
    if (v is T) return v;
    throw StateError(
      'Cannot deserialize ${v?.runtimeType} as $T.',
    );
  }

  @override
  Object? deserializeAs(Type targetType) {
    final v = value;
    if (v != null && v.runtimeType == targetType) return v;
    return null;
  }

  /// Converts this value to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    if (typeId != null) 'typeId': typeId,
    'value': value,
  };

  /// Creates a value from JSON.
  factory JsonWireSerializedValue.fromJson(Map<String, Object?> json) =>
      JsonWireSerializedValue(
        value: json['value'],
        typeId: json['typeId'] as String?,
      );
}
