/// Defines methods for marshalling and unmarshalling objects to and from a
/// wire format.
///
/// [TWireContainer]
abstract class WireMarshaller<TWireContainer> {
  /// Marshals the specified value of the given type into a wire format
  /// container.
  ///
  /// Returns:
  ///
  /// [value]
  ///
  /// [type]
  TWireContainer marshal({
    Object? value,
    Type? type,
    TWireContainer? data,
    Type? targetType,
  });
}
