import '../checkpoint_info.dart';
import 'checkpoint.dart';
import 'checkpoint_manager.dart';
import 'session_checkpoint_cache.dart';

/// An in-memory implementation of [CheckpointManager] that stores checkpoints
/// in a dictionary.
class InMemoryCheckpointManager implements CheckpointManager {
  InMemoryCheckpointManager(Map<String, SessionCheckpointCache<Checkpoint>> store) : store = store {
  }

  final Map<String, SessionCheckpointCache<Checkpoint>> store = {};

  SessionCheckpointCache<Checkpoint> getSessionStore(String sessionId) {
    SessionCheckpointCache<Checkpoint>? sessionStore;
    if (!this.store.containsKey(sessionId)) {
      sessionStore = this.store[sessionId] = new();
    }
    return sessionStore;
  }

  @override
  Future<CheckpointInfo> commitCheckpoint(String sessionId, Checkpoint checkpoint, ) {
    var sessionStore = this.getSessionStore(sessionId);
    CheckpointInfo key;
    do {
      key = new(sessionId);
    } while (!sessionStore.add(key, checkpoint));
    return new(key);
  }

  @override
  Future<Checkpoint> lookupCheckpoint(String sessionId, CheckpointInfo checkpointInfo, ) {
    Checkpoint value;
    if (!this.getSessionStore(sessionId).tryGet(checkpointInfo)) {
      throw StateError('Could not retrieve checkpoint with id ${checkpointInfo.checkpointId} for session ${sessionId}');
    }
    return new(value);
  }

  bool hasCheckpoints(String sessionId) {
    return this.getSessionStore(sessionId).hasCheckpoints;
  }

  (bool, CheckpointInfo??) tryGetLastCheckpoint(String sessionId) {
    // TODO(transpiler): implement out-param body
    throw UnimplementedError();
  }

  @override
  Future<Iterable<CheckpointInfo>> retrieveIndex(String sessionId, {CheckpointInfo? withParent, }) {
    return new(this.getSessionStore(sessionId).checkpointIndex.asReadOnly());
  }
}
