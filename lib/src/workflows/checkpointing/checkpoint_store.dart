import 'checkpoint.dart';

/// Stores durable workflow checkpoints.
abstract interface class CheckpointStore {
  /// Writes [checkpoint].
  Future<void> writeCheckpointAsync(Checkpoint checkpoint);

  /// Reads a checkpoint by [checkpointId].
  Future<Checkpoint?> readCheckpointAsync(String checkpointId);

  /// Lists checkpoints, optionally filtered by [sessionId].
  Future<List<Checkpoint>> listCheckpointsAsync({String? sessionId});

  /// Deletes a checkpoint by [checkpointId].
  Future<bool> deleteCheckpointAsync(String checkpointId);
}
