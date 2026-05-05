import '../executor_binding.dart';
import '../request_port.dart';
import '../workflow.dart';
import 'edge_info.dart';
import 'executor_info.dart';
import 'request_port_info.dart';
import 'type_id.dart';

class WorkflowInfo {
  WorkflowInfo(
    Map<String, ExecutorInfo> executors,
    Map<String, List<EdgeInfo>> edges,
    Set<RequestPortInfo> requestPorts,
    String startExecutorId,
    Set<String>? outputExecutorIds,
  ) : executors = executors,
      edges = edges,
      requestPorts = requestPorts,
      startExecutorId = startExecutorId,
      outputExecutorIds = outputExecutorIds {
    this.outputExecutorIds = outputExecutorIds ?? [];
  }

  final Map<String, ExecutorInfo> executors;

  final Map<String, List<EdgeInfo>> edges;

  final Set<RequestPortInfo> requestPorts;

  final TypeId? inputType;

  final String startExecutorId;

  final Set<String> outputExecutorIds;

  bool isMatch(Workflow workflow) {
    if (workflow == null) {
      return false;
    }
    if (this.startExecutorId != workflow.startExecutorId) {
      return false;
    }
    ExecutorBinding binding;
    if (workflow.executorBindings.length != this.executors.length ||
        this.executors.keys.any(
          (executorId) =>
              workflow.executorBindings.containsKey(executorId) &&
              !this.executors[executorId].isMatch(binding),
        )) {
      return false;
    }
    var edgeList;
    if (workflow.edges.length != this.edges.length ||
        this.edges.keys.any(
          (sourceId) =>
              // If the sourceId is! present in the workflow edges, or
              !workflow.edges.containsKey(sourceId) ||
              // If the edge list count does not match, or
              edgeList.length != this.edges[sourceId].length ||
              // If any edge in the workflow edge list does not match the corresponding edge in this.edges[sourceId]
              !edgeList.every(
                (edge) => this.edges[sourceId].any((e) => e.isMatch(edge)),
              ),
        )) {
      return false;
    }
    RequestPort? port;
    if (workflow.ports.length != this.requestPorts.length ||
        this.requestPorts.any(
          (portInfo) =>
              !workflow.ports.containsKey(portInfo.portId) ||
              !portInfo.requestType.isMatch(port.request) ||
              !portInfo.responseType.isMatch(port.response),
        )) {
      return false;
    }
    if (workflow.outputExecutors.length != this.outputExecutorIds.length ||
        this.outputExecutorIds.any(
          (id) => !workflow.outputExecutors.contains(id),
        )) {
      return false;
    }
    return true;
  }
}
