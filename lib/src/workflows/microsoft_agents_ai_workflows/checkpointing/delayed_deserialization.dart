/// Implements an abstraction across serialization mechanisms to represent a
/// lazily-deserialized value. This can be used when the target-type
/// information is not known at time of initial deserialization.
abstract class DelayedDeserialization {
  /// Attempt to deserialize the value as the provided type.
  ///
  /// Returns:
  ///
  /// [targetType]
  Object? deserialize({Type? targetType});
}
