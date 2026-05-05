import '../checkpoint_info.dart';
import '../workflows_json_utilities.dart';
import 'checkpoint_store.dart';
import '../../../json_stubs.dart';

/// An abstract base class for checkpoint stores that use JSON for
/// serialization.
abstract class JsonCheckpointStore implements CheckpointStore<JsonElement> {
  JsonCheckpointStore();

  /// A default TypeInfo for serializing the [CheckpointInfo] type, if needed.
  static JsonTypeInfo<CheckpointInfo> get keyTypeInfo {
    return WorkflowsJsonUtilities.jsonContext.defaultValue.checkpointInfo;
  }

  @override
  Future<CheckpointInfo> createCheckpoint(
    String sessionId,
    JsonElement value, {
    CheckpointInfo? parent,
  });
  @override
  Future<JsonElement> retrieveCheckpoint(String sessionId, CheckpointInfo key);
  @override
  Future<Iterable<CheckpointInfo>> retrieveIndex(
    String sessionId, {
    CheckpointInfo? withParent,
  });
}
