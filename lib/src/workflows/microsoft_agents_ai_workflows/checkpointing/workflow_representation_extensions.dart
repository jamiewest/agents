import '../workflow.dart';
import 'edge_info.dart';
import 'executor_info.dart';
import 'representation_extensions.dart';
import 'request_port_info.dart';
import 'workflow_info.dart';

/// Extension methods for converting [Workflow] to its checkpointing
/// representation.
extension WorkflowRepresentationExtensions on Workflow {
  WorkflowInfo toWorkflowInfo() {
    final executors = Map.fromEntries(
      executorBindings.values.map(
        (b) => MapEntry(b.id, b.toExecutorInfo()),
      ),
    );
    final edgeMap = Map.fromEntries(
      edges.entries.map(
        (e) => MapEntry<String, List<EdgeInfo>>(
          e.key,
          e.value.map((edge) => edge.toEdgeInfo()).toList(),
        ),
      ),
    );
    final inputPorts = ports.values
        .map((p) => p.toPortInfo())
        .toSet();
    return WorkflowInfo(
      executors,
      edgeMap,
      inputPorts,
      startExecutorId,
      outputExecutors,
    );
  }
}
