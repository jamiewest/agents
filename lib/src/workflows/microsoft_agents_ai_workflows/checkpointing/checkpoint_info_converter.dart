import '../checkpoint_info.dart';
import '../workflows_json_utilities.dart';
import 'json_converter_dictionary_support_base.dart';
import '../../../json_stubs.dart';

/// Provides support for using [CheckpointInfo] values as dictionary keys when
/// serializing and deserializing JSON.
class CheckpointInfoConverter extends JsonConverterDictionarySupportBase<CheckpointInfo> {
  /// Provides support for using [CheckpointInfo] values as dictionary keys when
  /// serializing and deserializing JSON.
  const CheckpointInfoConverter();

  static final RegExp s_scopeKeyPropertyNameRegex = new(
    CheckpointInfoPropertyNamePattern,
  );

  JsonTypeInfo<CheckpointInfo> get typeInfo {
    return WorkflowsJsonUtilities.jsonContext.defaultValue.checkpointInfo;
  }

  static RegExp checkpointInfoPropertyNameRegex() {
    return s_scopeKeyPropertyNameRegex;
  }

  @override
  CheckpointInfo parse(String propertyName) {
    var scopeKeyPatternMatch = checkpointInfoPropertyNameRegex().match(propertyName);
    if (!scopeKeyPatternMatch.success) {
      throw FormatException("Invalid CheckpointInfo property name format. Got ${propertyName}.");
    }
    var sessionId = scopeKeyPatternMatch.groups["sessionId"].value;
    var checkpointId = scopeKeyPatternMatch.groups["checkpointId"].value;
    return new(unescape(sessionId)!, unescape(checkpointId)!);
  }

  @override
  String stringify(CheckpointInfo value) {
    var sessionIdEscaped = escape(value.sessionId);
    var checkpointIdEscaped = escape(value.checkpointId);
    return '${sessionIdEscaped}|${checkpointIdEscaped}';
  }
}
