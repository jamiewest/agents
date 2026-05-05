import 'checkpoint_info.dart';

/// Debug information about the SuperStep that finished running.
class SuperStepCompletionInfo {
  /// Debug information about the SuperStep that finished running.
  SuperStepCompletionInfo(
    Iterable<String> activatedExecutors,
    {Iterable<String>? instantiatedExecutors = null, },
  ) : activatedExecutors = activatedExecutors;

  /// The unique identifiers of [Executor] instances that processed messages
  /// during this SuperStep
  final Set<String> activatedExecutors = [.. activatedExecutors];

  /// The unique identifiers of [Executor] instances newly created during this
  /// SuperStep
  final Set<String> instantiatedExecutors = [.. instantiatedExecutors ?? []];

  /// A flag indicating whether the managed state was written to during this
  /// SuperStep. If the run was started with checkpointing, any updated during
  /// the checkpointing process are also included.
  bool stateUpdated;

  /// A flag indicating whether there are messages pending delivery after this
  /// SuperStep.
  bool hasPendingMessages;

  /// A flag indicating whether there are requests pending delivery after this
  /// SuperStep.
  bool hasPendingRequests;

  /// Gets the [CheckpointInfo] corresponding to the checkpoint created at the
  /// end of this SuperStep. `null` if checkpointing was not enabled when the
  /// run was started.
  CheckpointInfo? checkpoint;

}
