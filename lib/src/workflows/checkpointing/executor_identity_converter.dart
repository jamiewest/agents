import '../execution/executor_identity.dart';
import 'json_converter_dictionary_support_base.dart';

/// Provides serialization and dictionary-key support for
/// [ExecutorIdentity] values.
///
/// [ExecutorIdentity.none] is represented as an empty string; other
/// identities are represented as `@{id}`.
final class ExecutorIdentityConverter
    extends JsonConverterDictionarySupportBase<ExecutorIdentity> {
  @override
  ExecutorIdentity? fromJson(Object? json) {
    if (json is String) return parse(json);
    return null;
  }

  @override
  Object? toJson(ExecutorIdentity value) => stringify(value);

  @override
  String stringify(ExecutorIdentity value) =>
      value == ExecutorIdentity.none ? '' : '@${value.id}';

  @override
  ExecutorIdentity parse(String key) {
    if (key.isEmpty) return ExecutorIdentity.none;
    if (key.startsWith('@')) {
      return ExecutorIdentity(key.substring(1));
    }
    throw FormatException(
      "Invalid ExecutorIdentity key: expected '' or '@{id}', got '$key'.",
    );
  }
}
