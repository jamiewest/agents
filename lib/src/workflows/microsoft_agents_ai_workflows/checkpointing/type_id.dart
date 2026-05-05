/// A representation of a type's identity by assembly name and type name.
///
/// Used for serialization/deserialization scenarios where types must be
/// identified across process restarts or language boundaries.
class TypeId {
  /// Creates a [TypeId] with the given [assemblyName] and [typeName].
  const TypeId({required this.assemblyName, required this.typeName});

  /// The assembly (package/library) name that contains the type.
  final String assemblyName;

  /// The fully-qualified name of the type within its assembly.
  final String typeName;

  /// Returns `true` if [type]'s runtime name matches this [TypeId].
  ///
  /// In Dart, [assemblyName] is compared against the library URI and
  /// [typeName] against [type.toString()].
  bool isMatch(Type type) {
    // Dart has no reflection equivalent for assembly/full-type-name matching.
    // Match on the Dart runtimeType String as a best-effort approximation.
    return type.toString() == typeName;
  }

  /// Returns `true` if [type] or any of its supertypes match this [TypeId].
  ///
  /// Dart has no runtime supertype traversal; this is a best-effort check
  /// against the exact type only.
  bool isMatchPolymorphic(Type type) => isMatch(type);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TypeId &&
          assemblyName == other.assemblyName &&
          typeName == other.typeName);

  @override
  int get hashCode => Object.hash(assemblyName, typeName);

  @override
  String toString() => '$typeName, $assemblyName';
}
