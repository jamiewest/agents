import 'package:clock/clock.dart';

/// Represents a checkpoint with a unique identifier.
class CheckpointInfo {
  /// Creates checkpoint info.
  CheckpointInfo(this.checkpointId, {DateTime? createdAt})
    : createdAt = createdAt ?? clock.now();

  /// Gets the checkpoint identifier.
  final String checkpointId;

  /// Gets the checkpoint creation time.
  final DateTime createdAt;

  /// Converts this checkpoint info to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'checkpointId': checkpointId,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Creates checkpoint info from JSON.
  factory CheckpointInfo.fromJson(Map<String, Object?> json) => CheckpointInfo(
    json['checkpointId']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
  );

  @override
  bool operator ==(Object other) =>
      other is CheckpointInfo &&
      other.checkpointId == checkpointId &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(checkpointId, createdAt);

  @override
  String toString() => checkpointId;
}
