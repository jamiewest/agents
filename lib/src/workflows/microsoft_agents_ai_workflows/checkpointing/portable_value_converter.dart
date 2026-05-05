import '../portable_value.dart';
import '../workflows_json_utilities.dart';
import 'delayed_deserialization.dart';
import 'json_marshaller.dart';
import 'json_wire_serialized_value.dart';
import '../../../json_stubs.dart';

/// Provides special handling for [PortableValue] serialization and
/// deserialization, enabling delayed deserialization of the inner value. This
/// is used to enable serialization/deserialization of objects whose type
/// information is not available at the time of initial deserialization, e.g.
/// user-defined state types. This operates in conjuction with
/// [DelayedDeserialization] and [PortableValue] to abstract away the
/// speicfics of a given serialization format in favor of [As`] and [Is`] and
/// related methods.
///
/// [marshaller]
class PortableValueConverter extends JsonConverter<PortableValue> {
  /// Provides special handling for [PortableValue] serialization and
  /// deserialization, enabling delayed deserialization of the inner value. This
  /// is used to enable serialization/deserialization of objects whose type
  /// information is not available at the time of initial deserialization, e.g.
  /// user-defined state types. This operates in conjuction with
  /// [DelayedDeserialization] and [PortableValue] to abstract away the
  /// speicfics of a given serialization format in favor of [As`] and [Is`] and
  /// related methods.
  ///
  /// [marshaller]
  const PortableValueConverter(JsonMarshaller marshaller);

  @override
  PortableValue? read(Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options, ) {
    var initial = reader.position;
    var baseTypeInfo = WorkflowsJsonUtilities.jsonContext.defaultValue.PortableValue;
    var maybeValue = JsonSerializer.deserialize(reader, baseTypeInfo);
    if (maybeValue == null) {
      throw FormatException('Could not deserialize a PortableValue from JSON at position ${initial}.');
    } else if (maybeValue.value is JsonElement) {
      final element = maybeValue.value as JsonElement;
      return PortableValue(maybeValue.typeId, JsonWireSerializedValue(marshaller, element));
    } else if (maybeValue.typeId.isMatch(maybeValue.value.runtimeType)) {
      return maybeValue;
    }
    throw FormatException('Deserialized PortableValue contains a value of type ${maybeValue.value.runtimeType} which does not match the expected type ${maybeValue.typeId} at position ${initial}.');
  }

  @override
  void write(Utf8JsonWriter writer, PortableValue value, JsonSerializerOptions options, ) {
    PortableValue proxyValue;
    if (value.isDelayedDeserialization && !value.isDeserialized) {
      if (value.value is JsonWireSerializedValue) {
        final jsonWireValue = value.value as JsonWireSerializedValue;
        proxyValue = new(value.typeId, jsonWireValue.data);
      } else {
        throw StateError("Cannot serialize a PortableValue that has not been deserialized. Please deserialize it with .as/asType() or Is/isType() methods first.");
      }
    } else {
      var element = marshaller.marshal(value.value, value.value.runtimeType);
      proxyValue = new(value.typeId, element);
    }
    var baseTypeInfo = WorkflowsJsonUtilities.jsonContext.defaultValue.PortableValue;
    JsonSerializer.serialize(writer, proxyValue, baseTypeInfo);
  }
}
