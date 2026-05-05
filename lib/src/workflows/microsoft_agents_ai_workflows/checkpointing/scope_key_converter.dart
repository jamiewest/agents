import '../scope_key.dart';
import '../workflows_json_utilities.dart';
import 'json_converter_dictionary_support_base.dart';
import '../../../json_stubs.dart';

/// Provides support for using [ScopeKey] values as dictionary keys when
/// serializing and deserializing JSON.
class ScopeKeyConverter extends JsonConverterDictionarySupportBase<ScopeKey> {
  ScopeKeyConverter();

  static final RegExp s_scopeKeyPropertyNameRegex = new(
    ScopeKeyPropertyNamePattern,
  );

  JsonTypeInfo<ScopeKey> get typeInfo {
    return WorkflowsJsonUtilities.jsonContext.defaultValue.scopeKey;
  }

  static RegExp scopeKeyPropertyNameRegex() {
    return s_scopeKeyPropertyNameRegex;
  }

  @override
  ScopeKey parse(String propertyName) {
    var scopeKeyPatternMatch = scopeKeyPropertyNameRegex().match(propertyName);
    if (!scopeKeyPatternMatch.success) {
      throw FormatException("Invalid ScopeKey property name format. Got ${propertyName}.");
    }
    var executorId = scopeKeyPatternMatch.groups["executorId"].value;
    var scopeName = scopeKeyPatternMatch.groups["scopeName"].value;
    var key = scopeKeyPatternMatch.groups["key"].value;
    return scopeKey(unescape(executorId)!,
                            unescape(scopeName, allowNullAndPad: true),
                            unescape(key)!);
  }

  @override
  String stringify(ScopeKey value) {
    var executorIdEscaped = escape(value.scopeId.executorId);
    var scopeNameEscaped = escape(value.scopeId.scopeName, allowNullAndPad: true);
    var keyEscaped = escape(value.key);
    return '${executorIdEscaped}|${scopeNameEscaped}|${keyEscaped}';
  }
}
