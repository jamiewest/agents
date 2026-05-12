import '../scope_id.dart';
import '../scope_key.dart';
import 'json_converter_dictionary_support_base.dart';

/// Provides serialization and dictionary-key support for [ScopeKey] values.
///
/// The wire format is `{executorId}|{scopeName}|{key}` where each component
/// has its `|` characters doubled to disambiguate from the delimiters.
/// A `null` scope name is encoded as an empty string; a non-null scope name
/// is prefixed with `@`.
final class ScopeKeyConverter
    extends JsonConverterDictionarySupportBase<ScopeKey> {
  /// The regex used to parse a [ScopeKey] property name.
  static final RegExp scopeKeyRegex = RegExp(
    r'^(?<executorId>((\|\|)|[^\|])*)'
    r'\|(?<scopeName>(@((\|\|)|[^\|])*)?)'
    r'\|(?<key>((\|\|)|[^\|])*)$',
  );

  @override
  ScopeKey? fromJson(Object? json) {
    if (json is String) return parse(json);
    return null;
  }

  @override
  Object? toJson(ScopeKey value) => stringify(value);

  @override
  String stringify(ScopeKey value) {
    final executorIdEsc =
        JsonConverterDictionarySupportBase.escape(value.scopeId.executorId);
    final scopeNameEsc = JsonConverterDictionarySupportBase.escape(
      value.scopeId.scopeName,
      allowNullAndPad: true,
    );
    final keyEsc = JsonConverterDictionarySupportBase.escape(value.key);
    return '$executorIdEsc|$scopeNameEsc|$keyEsc';
  }

  @override
  ScopeKey parse(String key) {
    final match = scopeKeyRegex.firstMatch(key);
    if (match == null) {
      throw FormatException('Invalid ScopeKey format: $key');
    }
    final executorId = JsonConverterDictionarySupportBase.unescape(
      match.namedGroup('executorId')!,
    )!;
    final scopeName = JsonConverterDictionarySupportBase.unescape(
      match.namedGroup('scopeName') ?? '',
      allowNullAndPad: true,
    );
    final k = JsonConverterDictionarySupportBase.unescape(
      match.namedGroup('key')!,
    )!;
    return ScopeKey(ScopeId(executorId, scopeName), k);
  }
}
