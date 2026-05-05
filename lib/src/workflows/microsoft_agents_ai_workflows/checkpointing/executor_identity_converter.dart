import '../execution/executor_identity.dart';
import '../workflows_json_utilities.dart';
import 'json_converter_dictionary_support_base.dart';
import '../../../json_stubs.dart';

/// Provides support for using [ExecutorIdentity] values as dictionary keys
/// when serializing and deserializing JSON.
class ExecutorIdentityConverter extends JsonConverterDictionarySupportBase<ExecutorIdentity> {
  /// Provides support for using [ExecutorIdentity] values as dictionary keys
  /// when serializing and deserializing JSON.
  const ExecutorIdentityConverter();

  JsonTypeInfo<ExecutorIdentity> get typeInfo {
    return WorkflowsJsonUtilities.jsonContext.defaultValue.executorIdentity;
  }

  @override
  ExecutorIdentity parse(String propertyName) {
    if (propertyName.length == 0) {
      return ExecutorIdentity.none;
    }
    if (propertyName[0] == '@') {
      return new() { Id = propertyName.substring(1) };
    }
    throw FormatException('Invalid ExecutorIdentity key Expecting empty String or a value that is prefixed with '@". Got ${propertyName}");
  }

  @override
  String stringify(ExecutorIdentity value) {
    return value == ExecutorIdentity.none
             ? ''
             : '@${value.id}';
  }
}
