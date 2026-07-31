import 'json_marshaller.dart';
import 'json_wire_serialized_value.dart';

/// Round-trips one payload type through JSON-safe wire values.
///
/// [toWire] receives the live payload and returns a JSON-encodable shape;
/// [fromWire] receives that shape (possibly after a JSON text round trip)
/// and rebuilds the typed payload.
class WireValueConverter {
  /// Creates a [WireValueConverter].
  const WireValueConverter({required this.toWire, required this.fromWire});

  /// Converts a live payload into a JSON-encodable value.
  final Object? Function(Object value) toWire;

  /// Rebuilds the typed payload from its wire value.
  final Object? Function(Object? wire) fromWire;
}

/// Converts values to and from checkpoint wire values.
class WireMarshaller {
  /// Creates a wire marshaller.
  const WireMarshaller({JsonMarshaller jsonMarshaller = const JsonMarshaller()})
    : _jsonMarshaller = jsonMarshaller;

  final JsonMarshaller _jsonMarshaller;

  /// Converters for payload types that aren't JSON-encodable, keyed by the
  /// payload's exact `runtimeType.toString()`.
  ///
  /// Checkpointing serializes pending message payloads to JSON text;
  /// payloads outside the JSON model (for example chat messages) fail
  /// there unless the host registers a converter for their type id. The
  /// same converter revives the payload on restore, keyed by the stored
  /// type id.
  static final Map<String, WireValueConverter> valueConverters =
      <String, WireValueConverter>{};

  /// Serializes [value] to a wire value.
  JsonWireSerializedValue serializeValue(Object? value) {
    final typeId = value?.runtimeType.toString();
    final converter = typeId == null ? null : valueConverters[typeId];
    return JsonWireSerializedValue(
      value: converter == null || value == null
          ? value
          : converter.toWire(value),
      typeId: typeId,
    );
  }

  /// Deserializes [value] from a wire value.
  Object? deserializeValue(JsonWireSerializedValue value) {
    final converter = value.typeId == null
        ? null
        : valueConverters[value.typeId];
    return converter == null ? value.value : converter.fromWire(value.value);
  }

  /// Serializes [value] to deterministic JSON text.
  String serializeJson(Object? value) => _jsonMarshaller.serialize(value);

  /// Deserializes deterministic JSON text.
  Object? deserializeJson(String json) => _jsonMarshaller.deserialize(json);
}
