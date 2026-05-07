import '../checkpoint_info.dart';
import '../checkpoint_manager.dart';

/// Provides checkpointing operations for a running workflow.
class CheckpointingHandle {
  /// Creates a checkpointing handle.
  CheckpointingHandle(this.checkpointManager);

  /// Gets the checkpoint manager.
  final CheckpointManager checkpointManager;

  /// Gets the most recent checkpoint info.
  CheckpointInfo? currentCheckpoint;

  /// Saves [checkpoint] and updates [currentCheckpoint].
  Future<CheckpointInfo> checkpointAsync(Object? checkpoint) async {
    currentCheckpoint = await checkpointManager.saveCheckpointAsync(checkpoint);
    return currentCheckpoint!;
  }

  /// Restores [checkpointInfo], or [currentCheckpoint] when omitted.
  Future<Object?> restoreAsync([CheckpointInfo? checkpointInfo]) {
    final info = checkpointInfo ?? currentCheckpoint;
    if (info == null) {
      throw StateError('No checkpoint is available to restore.');
    }
    return checkpointManager.restoreCheckpointAsync(info);
  }
}
