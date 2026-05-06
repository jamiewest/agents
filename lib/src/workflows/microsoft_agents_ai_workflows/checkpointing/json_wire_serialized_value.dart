import '../portable_value.dart';
import 'delayed_deserialization.dart';
import 'json_marshaller.dart';
import '../../../json_stubs.dart';

/// Represents a value serialized to the JSON format ([JsonMarshaller]). When
/// type information is not available during deserialization, this will wrap a
/// clone of the [JsonElement] to be deserialized later.
///
/// [serializer]
///
/// [data]
class JsonWireSerializedValue implements DelayedDeserialization {
  /// Represents a value serialized to the JSON format ([JsonMarshaller]). When
  /// type information is not available during deserialization, this will wrap a
  /// clone of the [JsonElement] to be deserialized later.
  ///
  /// [serializer]
  ///
  /// [data]
  const JsonWireSerializedValue(JsonMarshaller serializer, JsonElement data)
    : data = data;

  final JsonElement data = data.Clone();

  @override
  Object? deserialize({Type? targetType}) {
    return serializer.marshal(targetType, data);
  }

  @override
  bool equals(Object? obj) {
    if (obj == null) {
      return false;
    }
    if (obj is JsonWireSerializedValue) {
      final otherValue = obj as JsonWireSerializedValue;
      return JsonElement.deepEquals(this.data, otherValue.data);
    } else if (obj is JsonElement) {
      final element = obj as JsonElement;
      return this.data == element;
    } else if (obj is! DelayedDeserialization) {
      try {
        var otherElement = serializer.marshal(obj, obj.runtimeType);
        return JsonElement.deepEquals(this.data, otherElement);
      } catch (e, s) {
        {
          return false;
        }
      }
    }
    return false;
  }

  @override
  int hashCode {
    return this.data.hashCode;
  }
}
