import '../checkpoint_info.dart';

/// Emits traces for key step lifecycle events within a workflow execution.
abstract interface class IStepTracer {
  /// Records that [executorId] was activated.
  void traceActivated(String executorId);

  /// Records that a checkpoint was created.
  void traceCheckpointCreated(CheckpointInfo checkpoint);

  /// Records that [executorId] was instantiated.
  void traceInstantiated(String executorId);

  /// Records that the executor's state was published.
  void traceStatePublished();
}
