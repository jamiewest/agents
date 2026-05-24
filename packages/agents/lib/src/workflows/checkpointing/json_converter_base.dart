/// Abstract base for JSON converters that serialize and deserialize a
/// specific type [T].
abstract class JsonConverterBase<T> {
  /// Deserializes [json] into a [T], or `null` if conversion fails.
  T? fromJson(Object? json);

  /// Serializes [value] to a JSON-compatible object.
  Object? toJson(T value);
}
