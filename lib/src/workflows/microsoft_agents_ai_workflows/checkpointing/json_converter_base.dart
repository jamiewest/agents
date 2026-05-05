import '../../../json_stubs.dart';
/// Provides support for JSON serialization and deserialization using a
/// specified JsonTypeInfo.
///
/// [T]
abstract class JsonConverterBase<T> extends JsonConverter<T> {
  JsonConverterBase();

  final JsonTypeInfo<T> typeInfo;

  @override
  T? read(Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options, ) {
    var position = reader.position;
    return JsonSerializer.deserialize(reader, this.typeInfo) ??
            throw FormatException('Could not deserialize a ${T.name} from JSON at position ${position}');
  }

  @override
  void write(Utf8JsonWriter writer, T value, JsonSerializerOptions options, ) {
    JsonSerializer.serialize(writer, value, this.typeInfo);
  }
}
