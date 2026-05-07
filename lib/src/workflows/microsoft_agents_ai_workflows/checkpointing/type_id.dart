/// Identifies a serialized Dart type in checkpoint wire data.
class TypeId {
  /// Creates a type id.
  const TypeId(this.value);

  /// Gets the type id string.
  final String value;

  /// Creates a type id from [type].
  factory TypeId.fromType(Type type) => TypeId(type.toString());

  @override
  bool operator ==(Object other) => other is TypeId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
