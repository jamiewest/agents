import '../checkpoint_info.dart';
import 'checkpoint.dart';

/// A manager for storing and retrieving workflow execution checkpoints.
abstract class CheckpointManager {
  /// Commits the specified checkpoint and returns information that can be used
  /// to retrieve it later.
  ///
  /// Returns: A [CheckpointInfo] representing the incoming checkpoint.
  ///
  /// [sessionId] The identifier for the current session or execution context.
  ///
  /// [checkpoint] The checkpoint to commit.
  Future<CheckpointInfo> commitCheckpoint(
    String sessionId,
    Checkpoint checkpoint,
  );

  /// Retrieves the checkpoint associated with the specified checkpoint
  /// information.
  ///
  /// Returns: A [ValueTask] representing the asynchronous operation. The result
  /// contains the [Checkpoint] associated with the specified `checkpointInfo`.
  ///
  /// [sessionId] The identifier for the current session of execution context.
  ///
  /// [checkpointInfo] The information used to identify the checkpoint.
  Future<Checkpoint> lookupCheckpoint(
    String sessionId,
    CheckpointInfo checkpointInfo,
  );

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
}
