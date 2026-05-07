import 'json_marshaller.dart';
import 'json_wire_serialized_value.dart';

/// Converts values to and from checkpoint wire values.
class WireMarshaller {
  /// Creates a wire marshaller.
  const WireMarshaller({JsonMarshaller jsonMarshaller = const JsonMarshaller()})
    : _jsonMarshaller = jsonMarshaller;

  final JsonMarshaller _jsonMarshaller;

  /// Serializes [value] to a wire value.
  JsonWireSerializedValue serializeValue(Object? value) =>
      JsonWireSerializedValue(
        value: value,
        typeId: value?.runtimeType.toString(),
      );

  /// Deserializes [value] from a wire value.
  Object? deserializeValue(JsonWireSerializedValue value) => value.value;

  /// Serializes [value] to deterministic JSON text.
  String serializeJson(Object? value) => _jsonMarshaller.serialize(value);

  /// Deserializes deterministic JSON text.
  Object? deserializeJson(String json) => _jsonMarshaller.deserialize(json);
}
