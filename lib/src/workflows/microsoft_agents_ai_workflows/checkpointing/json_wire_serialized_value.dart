/// Stores a JSON-shaped value together with optional type metadata.
class JsonWireSerializedValue {
  /// Creates a JSON wire serialized value.
  const JsonWireSerializedValue({required this.value, this.typeId});

  /// Gets the serialized JSON-shaped value.
  final Object? value;

  /// Gets the optional type identifier.
  final String? typeId;

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
