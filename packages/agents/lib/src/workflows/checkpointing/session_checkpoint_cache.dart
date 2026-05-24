import '../checkpoint_info.dart';

/// Tracks checkpoints by workflow session.
class SessionCheckpointCache {
  final Map<String, List<CheckpointInfo>> _checkpointsBySession =
      <String, List<CheckpointInfo>>{};

  /// Adds [checkpointInfo] for [sessionId].
  void addCheckpoint(String sessionId, CheckpointInfo checkpointInfo) {
    (_checkpointsBySession[sessionId] ??= <CheckpointInfo>[]).add(
      checkpointInfo,
    );
  }

  /// Gets the latest checkpoint for [sessionId].
  CheckpointInfo? getLatestCheckpoint(String sessionId) {
    final checkpoints = _checkpointsBySession[sessionId];
    if (checkpoints == null || checkpoints.isEmpty) {
      return null;
    }
    return checkpoints.last;
  }

  /// Lists checkpoints for [sessionId].
  List<CheckpointInfo> listCheckpoints(String sessionId) =>
      List<CheckpointInfo>.unmodifiable(
        _checkpointsBySession[sessionId] ?? const <CheckpointInfo>[],
      );

  /// Clears checkpoints for [sessionId].
  void clearSession(String sessionId) =>
      _checkpointsBySession.remove(sessionId);
}
