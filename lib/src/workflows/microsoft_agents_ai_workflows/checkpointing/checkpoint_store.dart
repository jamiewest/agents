import '../checkpoint_info.dart';

/// Defines a contract for storing and retrieving checkpoints associated with
/// a specific session and key.
///
/// [TStoreObject] The type of Object to be stored as the value for each
/// checkpoint.
abstract class CheckpointStore<TStoreObject> {
  /// Asynchronously retrieves the collection of checkpoint information for the
  /// specified session identifier, optionally filtered by a parent checkpoint.
  ///
  /// Returns: A value task representing the asynchronous operation. The result
  /// contains a collection of [CheckpointInfo] objects associated with the
  /// specified session. The collection is empty if no checkpoints are found.
  ///
  /// [sessionId] The unique identifier of the session for which to retrieve
  /// checkpoint information. Cannot be null or empty.
  ///
  /// [withParent] An optional parent checkpoint to filter the results. If
  /// specified, only checkpoints with the given parent are returned; otherwise,
  /// all checkpoints for the session are included.
  Future<Iterable<CheckpointInfo>> retrieveIndex(
    String sessionId, {
    CheckpointInfo? withParent,
  });

  /// Asynchronously creates a checkpoint for the specified session and key,
  /// associating it with the provided value and optional parent checkpoint.
  ///
  /// Returns: A ValueTask that represents the asynchronous operation. The
  /// result contains the [CheckpointInfo] Object representing this stored
  /// checkpoint.
  ///
  /// [sessionId] The unique identifier of the session for which the checkpoint
  /// is being created. Cannot be null or empty.
  ///
  /// [value] The value to associate with the checkpoint. Cannot be null.
  ///
  /// [parent] The optional parent checkpoint information. If specified, the new
  /// checkpoint will be linked as a child of this parent.
  Future<CheckpointInfo> createCheckpoint(
    String sessionId,
    TStoreObject value, {
    CheckpointInfo? parent,
  });

  /// Asynchronously retrieves a checkpoint Object associated with the specified
  /// session and checkpoint key.
  ///
  /// Returns: A ValueTask that represents the asynchronous operation. The
  /// result contains the checkpoint Object associated with the specified
  /// session and key.
  ///
  /// [sessionId] The unique identifier of the session for which the checkpoint
  /// is to be retrieved. Cannot be null or empty.
  ///
  /// [key] The key identifying the specific checkpoint to retrieve. Cannot be
  /// null.
  Future<TStoreObject> retrieveCheckpoint(String sessionId, CheckpointInfo key);
}
