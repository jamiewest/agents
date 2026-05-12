import '../portable_value.dart';
import 'json_converter_base.dart';

/// Provides JSON serialization for [PortableValue] with support for lazy
/// deserialization of the inner value.
///
/// When deserializing, the raw JSON value is wrapped in a
/// `JsonWireSerializedValue` so that the actual type conversion is deferred
/// until the caller invokes [PortableValue.asValue] or related methods.
final class PortableValueConverter
    extends JsonConverterBase<PortableValue> {
  /// Creates a [PortableValueConverter].
  PortableValueConverter();

  @override
  PortableValue? fromJson(Object? json) {
    if (json is! Map) return null;
    return PortableValue.fromJson(json.cast<String, Object?>());
  }

  @override
  Object? toJson(PortableValue value) => value.toJson();
}
