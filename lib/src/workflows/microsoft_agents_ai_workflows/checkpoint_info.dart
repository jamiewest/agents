/// Represents a checkpoint with a unique identifier.
class CheckpointInfo {
  /// Initializes a new instance of the CheckpointInfo class with the specified
  /// session and checkpoint identifiers.
  ///
  /// [sessionId] The unique identifier for the session. Cannot be null or
  /// empty.
  ///
  /// [checkpointId] The unique identifier for the checkpoint. Cannot be null or
  /// empty.
  CheckpointInfo(String sessionId, {String? checkpointId = null})
    : sessionId = sessionId {
    this.checkpointId = checkpointId;
  }

  /// Gets the unique identifier for the current session.
  final String sessionId;

  /// The unique identifier for the checkpoint.
  late final String checkpointId;

  @override
  bool equals({CheckpointInfo? other, Object? obj}) {
    return other != null &&
        this.sessionId == other.sessionId &&
        this.checkpointId == other.checkpointId;
  }

  @override
  int getHashCode() {
    return HashCode.combine(this.sessionId, this.checkpointId);
  }

  @override
  String toString() {
    return 'checkpointInfo(sessionId: ${this.sessionId}, checkpointId: ${this.checkpointId})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CheckpointInfo &&
        sessionId == other.sessionId &&
        checkpointId == other.checkpointId;
  }

  @override
  int get hashCode {
    return Object.hash(sessionId, checkpointId);
  }
}
