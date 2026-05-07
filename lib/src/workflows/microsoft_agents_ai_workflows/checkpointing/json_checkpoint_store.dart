import 'checkpoint.dart';
import 'checkpoint_store.dart';
import 'json_marshaller.dart';

/// In-memory JSON checkpoint store.
class JsonCheckpointStore implements CheckpointStore {
  /// Creates a JSON checkpoint store.
  JsonCheckpointStore({JsonMarshaller jsonMarshaller = const JsonMarshaller()})
    : _jsonMarshaller = jsonMarshaller;

  final JsonMarshaller _jsonMarshaller;
  final Map<String, String> _documents = <String, String>{};

  /// Gets serialized checkpoint documents.
  Map<String, String> get documents =>
      Map<String, String>.unmodifiable(_documents);

  @override
  Future<void> writeCheckpointAsync(Checkpoint checkpoint) async {
    _documents[checkpoint.info.checkpointId] = _jsonMarshaller.serialize(
      checkpoint.toJson(),
    );
  }

  @override
  Future<Checkpoint?> readCheckpointAsync(String checkpointId) async {
    final document = _documents[checkpointId];
    if (document == null) {
      return null;
    }
    final json = _jsonMarshaller.deserialize(document)! as Map;
    return Checkpoint.fromJson(json.cast<String, Object?>());
  }

  @override
  Future<List<Checkpoint>> listCheckpointsAsync({String? sessionId}) async {
    final checkpoints = <Checkpoint>[];
    for (final checkpointId in _documents.keys.toList()..sort()) {
      final checkpoint = await readCheckpointAsync(checkpointId);
      if (checkpoint == null) {
        continue;
      }
      if (sessionId == null || checkpoint.sessionId == sessionId) {
        checkpoints.add(checkpoint);
      }
    }
    return checkpoints;
  }

  @override
  Future<bool> deleteCheckpointAsync(String checkpointId) async =>
      _documents.remove(checkpointId) != null;
}
