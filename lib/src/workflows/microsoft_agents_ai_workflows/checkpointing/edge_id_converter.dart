import '../edge_id.dart';
import 'json_converter_dictionary_support_base.dart';

/// Provides serialization and dictionary-key support for [EdgeId] values.
///
/// [EdgeId] values are represented as their string [EdgeId.value] directly.
final class EdgeIdConverter
    extends JsonConverterDictionarySupportBase<EdgeId> {
  @override
  EdgeId? fromJson(Object? json) {
    if (json is String) return EdgeId(json);
    return null;
  }

  @override
  Object? toJson(EdgeId value) => value.value;

  @override
  String stringify(EdgeId value) => value.value;

  @override
  EdgeId parse(String key) => EdgeId(key);
}
