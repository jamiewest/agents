import 'checkpoint_info.dart';
import 'checkpointing/checkpoint.dart';
import 'checkpointing/checkpoint_manager.dart';
import 'checkpointing/checkpoint_manager_impl.dart';
import 'checkpointing/checkpoint_store.dart';
import 'checkpointing/in_memory_checkpoint_manager.dart';
import 'checkpointing/wire_marshaller.dart';
import '../../json_stubs.dart';

/// A manager for storing and retrieving workflow execution checkpoints.
class CheckpointManager {
  CheckpointManager(CheckpointManager impl) : _impl = impl {
  }

  final CheckpointManager _impl;

  /// Gets the default in-memory checkpoint manager instance.
  static final CheckpointManager defaultValue = CreateInMemory();

  static CheckpointManagerImpl<TStoreObject> createImpl<TStoreObject>(
    WireMarshaller<TStoreObject> marshaller,
    CheckpointStore<TStoreObject> store,
  ) {
    return CheckpointManagerImpl<TStoreObject>(marshaller, store);
  }

  /// Creates a new instance of [CheckpointManager] that uses the specified
  /// marshaller and store.
  ///
  /// Returns:
  static CheckpointManager createInMemory() {
    return new(inMemoryCheckpointManager());
  }

  /// Creates a new instance of the CheckpointManager that uses JSON
  /// serialization for checkpoint data.
  ///
  /// Returns: A CheckpointManager instance configured to serialize checkpoint
  /// data as JSON.
  ///
  /// [store] The checkpoint store to use for persisting and retrieving
  /// checkpoint data as JSON elements. Cannot be null.
  ///
  /// [customOptions] Optional custom JSON serializer options to use for
  /// serialization and deserialization. Must be provided if using custom types
  /// in messages or state.
  static CheckpointManager createJson(
    CheckpointStore<JsonElement> store,
    {JsonSerializerOptions? customOptions, },
  ) {
    var marshaller = new(customOptions);
    return new(createImpl(marshaller, store));
  }

  Future<CheckpointInfo> commitCheckpoint(String sessionId, Checkpoint checkpoint, ) {
    return this._impl.commitCheckpointAsync(sessionId, checkpoint);
  }

  Future<Checkpoint> lookupCheckpoint(String sessionId, CheckpointInfo checkpointInfo, ) {
    return this._impl.lookupCheckpointAsync(sessionId, checkpointInfo);
  }

  Future<Iterable<CheckpointInfo>> retrieveIndex(String sessionId, CheckpointInfo? withParent, ) {
    return this._impl.retrieveIndexAsync(sessionId, withParent);
  }
}
