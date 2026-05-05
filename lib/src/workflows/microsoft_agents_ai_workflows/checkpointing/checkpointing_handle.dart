import 'package:extensions/system.dart';
import '../checkpoint_info.dart';

abstract class CheckpointingHandle {
  /// Gets a value indicating whether checkpointing is enabled for the current
  /// operation or process.
  bool get isCheckpointingEnabled;

  /// Gets a read-only list of checkpoint information associated with the
  /// current context.
  List<CheckpointInfo> get checkpoints;

  /// Restores the system state from the specified checkpoint asynchronously.
  ///
  /// Remarks: This contract is used by live runtime restore paths.
  /// Implementations may re-emit pending external request events as part of the
  /// restore once the active event stream is ready to observe them. Initial
  /// resume paths that create a new event stream should restore state first and
  /// defer any replay until after the subscriber is attached, rather than
  /// calling this contract directly before the stream is ready.
  ///
  /// Returns: A [ValueTask] that represents the asynchronous restore operation.
  ///
  /// [checkpointInfo] The checkpoint information that identifies the state to
  /// restore. Cannot be null.
  ///
  /// [cancellationToken] A cancellation token that can be used to cancel the
  /// restore operation.
  Future restoreCheckpoint(
    CheckpointInfo checkpointInfo, {
    CancellationToken? cancellationToken,
  });
}
