import '../checkpoint_info.dart';
import '../checkpoint_manager.dart';
import 'checkpoint.dart';
import 'checkpoint_store.dart';

/// Default checkpoint manager backed by a [CheckpointStore].
class CheckpointManagerImpl implements CheckpointManager {
  /// Creates a checkpoint manager.
  CheckpointManagerImpl(this.store, {this.sessionId = 'default'});

  /// Gets the underlying checkpoint store.
  final CheckpointStore store;

  /// Gets the default session id used for payload-only checkpoints.
  final String sessionId;

  var _nextCheckpointId = 0;

  @override
  Future<CheckpointInfo> saveCheckpointAsync(Object? checkpoint) async {
    final materialized = checkpoint is Checkpoint
        ? checkpoint
        : Checkpoint(
            info: _createCheckpointInfo(),
            sessionId: sessionId,
            payload: checkpoint,
          );
    await store.writeCheckpointAsync(materialized);
    return materialized.info;
  }

  @override
  Future<Object?> restoreCheckpointAsync(CheckpointInfo checkpointInfo) async {
    final checkpoint = await store.readCheckpointAsync(
      checkpointInfo.checkpointId,
    );
    return checkpoint?.payload;
  }

  /// Saves a typed [checkpoint].
  Future<CheckpointInfo> saveTypedCheckpointAsync(Checkpoint checkpoint) =>
      saveCheckpointAsync(checkpoint);

  /// Restores a typed checkpoint by [checkpointInfo].
  Future<Checkpoint?> restoreTypedCheckpointAsync(
    CheckpointInfo checkpointInfo,
  ) => store.readCheckpointAsync(checkpointInfo.checkpointId);

  CheckpointInfo _createCheckpointInfo() =>
      CheckpointInfo('checkpoint-${++_nextCheckpointId}');
}
