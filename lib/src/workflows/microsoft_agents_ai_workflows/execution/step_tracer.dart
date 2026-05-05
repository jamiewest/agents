import '../checkpoint_info.dart';

abstract class StepTracer {
  void traceActivated(String executorId);
  void traceCheckpointCreated(CheckpointInfo checkpoint);
  void traceIntantiated(String executorId);
  void traceStatePublished();
}
