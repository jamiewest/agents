import 'checkpoint_info.dart';

/// Minimal checkpoint manager contract for workflow run APIs.
abstract interface class CheckpointManager {
  /// Saves a checkpoint and returns its info.
  Future<CheckpointInfo> saveCheckpointAsync(Object? checkpoint);

  /// Restores a checkpoint payload.
  Future<Object?> restoreCheckpointAsync(CheckpointInfo checkpointInfo);
}
