import '../checkpoint_info.dart';
import '../edge_id.dart';
import '../execution/runner_state_data.dart';
import '../portable_value.dart';
import '../scope_key.dart';
import 'workflow_info.dart';

class Checkpoint {
  Checkpoint(
    int stepNumber,
    WorkflowInfo workflow,
    RunnerStateData runnerData,
    Map<ScopeKey, PortableValue> stateData,
    Map<EdgeId, PortableValue> edgeStateData, {
    CheckpointInfo? parent = null,
  }) : stepNumber = stepNumber,
       workflow = workflow,
       runnerData = runnerData,
       stateData = stateData,
       edgeStateData = edgeStateData {
    this.parent = parent;
  }

  final int stepNumber;

  final WorkflowInfo workflow;

  final RunnerStateData runnerData;

  final Map<ScopeKey, PortableValue> stateData = {};

  final Map<EdgeId, PortableValue> edgeStateData = {};

  late final CheckpointInfo? parent;

  bool get isInitial {
    return this.stepNumber == -1;
  }
}
