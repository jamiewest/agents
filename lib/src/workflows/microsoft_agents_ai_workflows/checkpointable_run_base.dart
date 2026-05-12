import 'checkpoint_info.dart';

/// Base contract for run handles that support checkpointing.
///
/// Both [Run] and [StreamingRun] satisfy this interface; callers can depend
/// on it when they only need checkpoint-related state.
abstract interface class CheckpointableRun {
  /// Gets the most recent checkpoint produced by this run, if any.
  CheckpointInfo? get lastCheckpoint;
}
