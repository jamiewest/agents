import 'dart:convert';

/// Serializes JSON-shaped checkpoint values deterministically.
class JsonMarshaller {
  /// Creates a JSON marshaller.
  const JsonMarshaller();

  /// Serializes [value] to JSON.
  String serialize(Object? value) => jsonEncode(_normalize(value));

  /// Deserializes [json] into a JSON-shaped Dart value.
  Object? deserialize(String json) => jsonDecode(json);

  Object? _normalize(Object? value) {
    if (value is Map) {
      final result = <String, Object?>{};
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      for (final key in keys) {
        result[key] = _normalize(value[key]);
      }
      return result;
    }
    if (value is Iterable && value is! String) {
      return value.map(_normalize).toList();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    return value;
  }
}
