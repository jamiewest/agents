import 'checkpoint_manager_impl.dart';
import 'json_checkpoint_store.dart';

/// In-memory checkpoint manager.
class InMemoryCheckpointManager extends CheckpointManagerImpl {
  /// Creates an in-memory checkpoint manager.
  factory InMemoryCheckpointManager({String sessionId = 'default'}) {
    final store = JsonCheckpointStore();
    return InMemoryCheckpointManager._(store, sessionId);
  }

  // The explicit initializer keeps a typed reference to the concrete store.
  // ignore: use_super_parameters
  InMemoryCheckpointManager._(JsonCheckpointStore store, String sessionId)
    : jsonStore = store,
      super(store, sessionId: sessionId);

  /// Gets the in-memory JSON store.
  final JsonCheckpointStore jsonStore;
}
