import 'json_converter_base.dart';
import '../../../json_stubs.dart';

/// Provides support for using `T` values as dictionary keys when serializing
/// and deserializing JSON. It chains to the provided [JsonTypeInfo] for
/// serialization and deserialization when not used as a property name.
///
/// [T]
abstract class JsonConverterDictionarySupportBase<T> extends JsonConverterBase<T> {
  JsonConverterDictionarySupportBase();

  String stringify(T value);
  T parse(String propertyName);
  static String escape(
    String? value,
    {char? escapeChar, bool? allowNullAndPad, String? componentName, },
  ) {
    if (!allowNullAndPad && value == null) {
      throw FormatException("Invalid ${componentName} ${value}. Expecting non-null String.");
    }
    if (value == null) {
      return '';
    }
    var unescaped = escapeChar.toString();
    var escaped = new(escapeChar, 2);
    if (allowNullAndPad) {
      return '@${value.replaceAll(unescaped, escaped)}';
    }
    return value.replaceAll(unescaped, escaped);
  }

  static String? unescape(
    String value,
    {char? escapeChar, bool? allowNullAndPad, String? componentName, },
  ) {
    if (value.length == 0) {
      if (!allowNullAndPad) {
        throw FormatException("Invalid $componentName '$value'. Expecting empty String or a value that is prefixed with '\@'.");
      }
      return null;
    }
    if (allowNullAndPad && value[0] != '@') {
      throw FormatException("Invalid ${componentName} component ${value}. Expecting empty String or a value that is prefixed with "@'.');
    }
    if (allowNullAndPad) {
      value = value.substring(1);
    }
    var unescaped = escapeChar.toString();
    var escaped = new(escapeChar, 2);
    return value.replaceAll(escaped, unescaped);
  }

  @override
  T readAsPropertyName(Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options, ) {
    var position = reader.position;
    var propertyName = reader.getString() ??
            throw FormatException('Got null trying to read property name at position ${position}');
    return this.parse(propertyName);
  }

  @override
  void writeAsPropertyName(Utf8JsonWriter writer, T value, JsonSerializerOptions options, ) {
    var propertyName = this.stringify(value);
    writer.writePropertyName(propertyName);
  }
}
