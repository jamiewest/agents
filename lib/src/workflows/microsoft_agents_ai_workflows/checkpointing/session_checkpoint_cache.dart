import '../checkpoint_info.dart';

class SessionCheckpointCache<TStoreObject> {
  SessionCheckpointCache({List<CheckpointInfo>? checkpointIndex = null, Map<CheckpointInfo, TStoreObject>? cache = null, }) {
    this.checkpointIndex = checkpointIndex;
    this.cache = cache;
  }

  final List<CheckpointInfo> checkpointIndex = [];

  final Map<CheckpointInfo, TStoreObject> cache = {};

  Iterable<CheckpointInfo> get index {
    return this.checkpointIndex;
  }

  bool isInIndex(CheckpointInfo key) {
    return this.cache.containsKey(key);
  }

  (bool, TStoreObject?) tryGet(CheckpointInfo key) {
    // TODO(transpiler): implement out-param body
    throw UnimplementedError();
  }

  CheckpointInfo add(TStoreObject value, {String? sessionId, CheckpointInfo? key, }) {
    CheckpointInfo key;
    do {
      key = new(sessionId);
    } while (!this.add(key, value));
    return key;
  }

  bool get hasCheckpoints {
    return this.checkpointIndex.length > 0;
  }

  (bool, CheckpointInfo?) tryGetLastCheckpointInfo() {
    if (this.hasCheckpoints) {
      return (true, this.checkpointIndex[this.checkpointIndex.length - 1]);
    }
    return (false, default);
  }
}
