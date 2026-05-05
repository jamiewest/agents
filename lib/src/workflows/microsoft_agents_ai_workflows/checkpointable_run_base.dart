import 'package:extensions/system.dart';
import 'checkpoint_info.dart';
import 'checkpointing/checkpointing_handle.dart';

/// Represents a base Object for a workflow run that may support
/// checkpointing.
abstract class CheckpointableRunBase {
  CheckpointableRunBase(CheckpointingHandle checkpointingHandle)
    : _checkpointingHandle = checkpointingHandle {
  }

  final CheckpointingHandle _checkpointingHandle;

  /// Gets the most recent checkpoint information.
  final CheckpointInfo? lastCheckpoint;

  bool get isCheckpointingEnabled {
    return this._checkpointingHandle.isCheckpointingEnabled;
  }

  List<CheckpointInfo> get checkpoints {
    return this._checkpointingHandle.checkpoints ?? [];
  }

  Future restoreCheckpoint(
    CheckpointInfo checkpointInfo, {
    CancellationToken? cancellationToken,
  }) {
    return this._checkpointingHandle.restoreCheckpointAsync(
      checkpointInfo,
      cancellationToken,
    );
  }
}
