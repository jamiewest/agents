import '../checkpoint_info.dart';
import 'checkpoint.dart';
import 'checkpoint_manager.dart';
import 'checkpoint_store.dart';
import 'wire_marshaller.dart';

class CheckpointManagerImpl<TStoreObject> implements CheckpointManager {
  CheckpointManagerImpl(
    WireMarshaller<TStoreObject> marshaller,
    CheckpointStore<TStoreObject> store,
  ) : _marshaller = marshaller,
      _store = store {
  }

  final WireMarshaller<TStoreObject> _marshaller;

  final CheckpointStore<TStoreObject> _store;

  @override
  Future<CheckpointInfo> commitCheckpoint(
    String sessionId,
    Checkpoint checkpoint,
  ) {
    var storeObject = this._marshaller.marshal(checkpoint);
    return this._store.createCheckpointAsync(
      sessionId,
      storeObject,
      checkpoint.parent,
    );
  }

  @override
  Future<Checkpoint> lookupCheckpoint(
    String sessionId,
    CheckpointInfo checkpointInfo,
  ) async {
    var result = await this._store
        .retrieveCheckpointAsync(sessionId, checkpointInfo)
        ;
    return this._marshaller.marshal<Checkpoint>(result);
  }

  @override
  Future<Iterable<CheckpointInfo>> retrieveIndex(
    String sessionId, {
    CheckpointInfo? withParent,
  }) {
    return this._store.retrieveIndexAsync(sessionId, withParent);
  }
}
