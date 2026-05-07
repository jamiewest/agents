/// Represents a checkpoint with a unique identifier.
class CheckpointInfo {
  /// Creates checkpoint info.
  CheckpointInfo(this.checkpointId, {DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();

  /// Gets the checkpoint identifier.
  final String checkpointId;

  /// Gets the checkpoint creation time.
  final DateTime createdAt;

  @override
  String toString() => checkpointId;
}
