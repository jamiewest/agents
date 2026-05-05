import 'dart:convert' as convert;

/// Stub types for C# System.Text.Json types.
/// These are placeholders until a proper Dart serialization strategy is
/// implemented. The intent is preserved from the original C# source.

/// Mirrors C# System.Text.Json.JsonSerializerOptions.
class JsonSerializerOptions {
  JsonSerializerOptions([JsonSerializerOptions? copyFrom]) {
    if (copyFrom != null) {
      converters.addAll(copyFrom.converters);
      typeInfoResolverChain.addAll(copyFrom.typeInfoResolverChain);
      typeInfoResolver = copyFrom.typeInfoResolver;
    }
  }

  final List<Object?> converters = [];
  final List<Object?> typeInfoResolverChain = [];
  Object? typeInfoResolver;
  Object? encoder;
  bool _readOnly = false;

  void makeReadOnly() => _readOnly = true;
  bool get isReadOnly => _readOnly;

  bool tryGetTypeInfo(Type type, {JsonTypeInfo? outTypeInfo}) => false;
}

/// Mirrors C# System.Text.Json.JsonElement (a parsed JSON value).
/// In Dart, JSON values are plain Dart objects from dart:convert.
class JsonElement {
  final Object? _value;

  const JsonElement(this._value);

  Object? get value => _value;

  JsonElement clone() => JsonElement(_value);

  static bool deepEquals(JsonElement? a, JsonElement? b) {
    return convert.json.encode(a?._value) == convert.json.encode(b?._value);
  }

  @override
  bool operator ==(Object other) {
    if (other is JsonElement) return deepEquals(this, other);
    return false;
  }

  @override
  int get hashCode => convert.json.encode(_value).hashCode;

  @override
  String toString() => convert.json.encode(_value);
}

/// Mirrors C# System.Text.Json.Serialization.Metadata.JsonTypeInfo<T>.
abstract class JsonTypeInfo<T> {
  const JsonTypeInfo();
}

/// Mirrors C# System.Text.Json.Utf8JsonReader.
class Utf8JsonReader {
  int get position => 0;
  String? getString() => null;
}

/// Mirrors C# System.Text.Json.Utf8JsonWriter.
class Utf8JsonWriter {
  void writePropertyName(String name) {}
}

/// Mirrors C# System.Text.Json.JsonSerializer.
class JsonSerializer {
  static bool get isReflectionEnabledByDefault => false;

  static T? deserialize<T>(Object? data, [JsonTypeInfo<T>? typeInfo]) {
    if (data is String) {
      return convert.json.decode(data) as T?;
    }
    return data as T?;
  }

  static String serialize(Object? value, [Object? typeInfo]) {
    return convert.json.encode(value);
  }

  static JsonElement serializeToElement(
    Object? value, [
    Object? typeInfo,
  ]) {
    return JsonElement(value);
  }
}

/// Mirrors C# System.Text.Json.Serialization.JsonConverter<T>.
abstract class JsonConverter<T> {
  T? read(Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options);
  void write(Utf8JsonWriter writer, T value, JsonSerializerOptions options);

  T readAsPropertyName(
    Utf8JsonReader reader,
    Type typeToConvert,
    JsonSerializerOptions options,
  ) => throw UnimplementedError();

  void writeAsPropertyName(
    Utf8JsonWriter writer,
    T value,
    JsonSerializerOptions options,
  ) => throw UnimplementedError();
}
