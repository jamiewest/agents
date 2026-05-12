/// Supports lazy deserialization of a value when the target type is not
/// known until retrieval time.
abstract interface class IDelayedDeserialization {
  /// Deserializes the stored value as [T].
  T deserialize<T>();

  /// Deserializes the stored value as [targetType], or returns `null`.
  Object? deserializeAs(Type targetType);
}
