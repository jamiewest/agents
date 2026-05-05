import '../edge_id.dart';
import '../workflows_json_utilities.dart';
import 'json_converter_dictionary_support_base.dart';
import '../../../json_stubs.dart';

/// Provides support for using [EdgeId] values as dictionary keys when
/// serializing and deserializing JSON.
class EdgeIdConverter extends JsonConverterDictionarySupportBase<EdgeId> {
  EdgeIdConverter();

  JsonTypeInfo<EdgeId> get typeInfo {
    return WorkflowsJsonUtilities.jsonContext.defaultValue.edgeId;
  }

  @override
  EdgeId parse(String propertyName) {
    int edgeId;
    if (int.tryParse(propertyName)) {
      return new(edgeId);
    }
    throw FormatException("Cannot deserialize EdgeId from JSON propery name ${propertyName}");
  }

  @override
  String stringify(EdgeId value) {
    return value.edgeIndex.toString();
  }
}
