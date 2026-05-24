import 'checkpoint_info.dart';

/// Debug information about the SuperStep that finished running.
class SuperStepCompletionInfo {
  /// Creates super-step completion info.
  SuperStepCompletionInfo(
    Iterable<String> activatedExecutors,
    Iterable<String> instantiatedExecutors, {
    this.hasPendingMessages = false,
    this.hasPendingRequests = false,
    this.stateUpdated = false,
    this.checkpoint,
  }) : activatedExecutors = List<String>.unmodifiable(activatedExecutors),
       instantiatedExecutors = List<String>.unmodifiable(instantiatedExecutors);

  /// Gets executor IDs that processed messages during this SuperStep.
  final List<String> activatedExecutors;

  /// Gets executor IDs newly created during this SuperStep.
  final List<String> instantiatedExecutors;

  /// Gets whether messages remain pending after this SuperStep.
  final bool hasPendingMessages;

  /// Gets whether external requests remain pending after this SuperStep.
  final bool hasPendingRequests;

  /// Gets whether managed state was updated during this SuperStep.
  final bool stateUpdated;

  /// Gets checkpoint info created at the end of this SuperStep, if any.
  final CheckpointInfo? checkpoint;
}
