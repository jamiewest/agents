import 'package:extensions/system.dart';
import '../request_port.dart';
import '../checkpointing/checkpoint.dart';
import '../edge.dart';
import '../edge_id.dart';
import '../external_response.dart';
import '../portable_value.dart';
import '../workflow.dart';
import 'delivery_mapping.dart';
import 'edge_runner.dart';
import 'executor_identity.dart';
import 'message_envelope.dart';
import 'response_edge_runner.dart';
import 'runner_context.dart';
import 'step_tracer.dart';
import '../../../map_extensions.dart';

class EdgeMap {
  EdgeMap(
    RunnerContext runContext,
    StepTracer? stepTracer,
    {Workflow? workflow = null, Map<String, Set<Edge>>? workflowEdges = null, Iterable<RequestPort>? workflowPorts = null, String? startExecutorId = null, }
  ) : _stepTracer = stepTracer;

  final Map<EdgeId, EdgeRunner> _edgeRunners = {};

  final Map<EdgeId, StatefulEdgeRunner> _statefulRunners = {};

  final Map<String, ResponseEdgeRunner> _portEdgeRunners;

  final ResponseEdgeRunner _inputRunner;

  final StepTracer? _stepTracer;

  Future<DeliveryMapping?> prepareDeliveryForEdge(
    Edge edge,
    MessageEnvelope message,
    {CancellationToken? cancellationToken, }
  ) {
    var id = edge.data.id;
    EdgeRunner? edgeRunner;
    if (!this._edgeRunners.containsKey(id)) {
      throw StateError('Edge ${edge} not found in the edge map.');
    }
    return edgeRunner.chaseEdgeAsync(message, this._stepTracer, cancellationToken);
  }

  bool tryRegisterPort(RunnerContext runContext, String executorId, RequestPort port, ) {
    return this._portEdgeRunners.tryAdd(
      port.id,
      ResponseEdgeRunner.forPort(runContext, executorId, port),
    );
  }

  Future<DeliveryMapping?> prepareDeliveryForInput(
    MessageEnvelope message,
    {CancellationToken? cancellationToken, }
  ) {
    return this._inputRunner.chaseEdgeAsync(message, this._stepTracer, cancellationToken);
  }

  Future<DeliveryMapping?> prepareDeliveryForResponse(
    ExternalResponse response,
    {CancellationToken? cancellationToken, }
  ) {
    ResponseEdgeRunner portRunner;
    if (!this._portEdgeRunners.containsKey(response.portInfo.portId)) {
      throw StateError('Port ${response.portInfo.portId} not found in the edge map.');
    }
    return portRunner.chaseEdgeAsync(
      messageEnvelope(response, ExecutorIdentity.none),
      this._stepTracer,
      cancellationToken,
    );
  }

  (bool, String?) tryGetResponsePortExecutorId(String portId) {
    if (this._portEdgeRunners.tryGetValue(portId)) {
      return (true, portRunner.executorId);
    }
    return (false, null);
  }

  Future<Map<EdgeId, PortableValue>> exportState() async {
    var exportedStates = [];
    for (final id in this._statefulRunners.keys) {
      exportedStates[id] = await this._statefulRunners[id].exportStateAsync();
    }
    return exportedStates;
  }

  Future importState(Checkpoint checkpoint) async {
    var importedState = checkpoint.edgeStateData;
    for (final id in importedState.keys) {
      var exportedState = importedState[id];
      await this._statefulRunners[id].importStateAsync(exportedState);
    }
  }
}
