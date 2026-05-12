import '../checkpoint_info.dart';
import 'json_converter_dictionary_support_base.dart';

/// Provides serialization and dictionary-key support for
/// [CheckpointInfo] values.
///
/// The key format is the escaped [CheckpointInfo.checkpointId].
final class CheckpointInfoConverter
    extends JsonConverterDictionarySupportBase<CheckpointInfo> {
  @override
  CheckpointInfo? fromJson(Object? json) {
    if (json is Map) {
      return CheckpointInfo.fromJson(json.cast<String, Object?>());
    }
    if (json is String) return parse(json);
    return null;
  }

  @override
  Object? toJson(CheckpointInfo value) => value.toJson();

  @override
  String stringify(CheckpointInfo value) =>
      JsonConverterDictionarySupportBase.escape(value.checkpointId);

  @override
  CheckpointInfo parse(String key) => CheckpointInfo(
    JsonConverterDictionarySupportBase.unescape(key)!,
  );
}
