import 'package:extensions/system.dart';
import '../workflow_event.dart';
import 'super_step_runner.dart';

abstract class SuperStepJoinContext {
  bool get isCheckpointingEnabled;
  bool get concurrentRunsEnabled;
  Future forwardWorkflowEvent(
    WorkflowEvent workflowEvent, {
    CancellationToken? cancellationToken,
  });
  Future sendMessage<TMessage>(
    String senderId,
    TMessage message, {
    CancellationToken? cancellationToken,
  });
  Future yieldOutput<TOutput>(
    String senderId,
    TOutput output, {
    CancellationToken? cancellationToken,
  });
  Future<String> attachSuperstep(
    SuperStepRunner superStepRunner, {
    CancellationToken? cancellationToken,
  });
  Future<bool> detachSuperstep(String id);
}
