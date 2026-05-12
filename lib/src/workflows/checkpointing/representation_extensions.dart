import '../checkpoint_info.dart';
import '../direct_edge_data.dart';
import '../edge.dart';
import '../executor_binding.dart';
import '../fan_in_edge_data.dart';
import '../fan_out_edge_data.dart';
import '../request_port.dart';
import '../workflow.dart';
import 'checkpoint_info_converter.dart';
import 'direct_edge_info.dart';
import 'edge_info.dart';
import 'executor_info.dart';
import 'fan_in_edge_info.dart';
import 'fan_out_edge_info.dart';
import 'request_port_info.dart';
import 'workflow_info.dart';

/// Converts [ExecutorBinding] instances to their checkpoint representation.
extension ExecutorBindingRepresentation on ExecutorBinding {
  /// Returns an [ExecutorInfo] describing this binding.
  ExecutorInfo toExecutorInfo() => ExecutorInfo(
    executorId: id,
    supportsConcurrentSharedExecution:
        supportsConcurrentSharedExecution,
    supportsResetting: supportsResetting,
  );
}

/// Converts [Edge] instances to their checkpoint representation.
extension EdgeRepresentation on Edge {
  /// Returns an [EdgeInfo] describing this edge.
  EdgeInfo toEdgeInfo() {
    final d = data;
    if (d is DirectEdgeData) {
      return DirectEdgeInfo(
        edgeId: d.id.value,
        sourceExecutorId: d.sourceExecutorId,
        targetExecutorId: d.targetExecutorId,
        messageType: d.messageType?.toString(),
      );
    }
    if (d is FanOutEdgeData) {
      return FanOutEdgeInfo(
        edgeId: d.id.value,
        sourceExecutorId: d.sourceExecutorId,
        targetExecutorIds: d.targetExecutorIds,
      );
    }
    if (d is FanInEdgeData) {
      return FanInEdgeInfo(
        edgeId: d.id.value,
        sourceExecutorIds: d.sourceExecutorIds,
        targetExecutorId: d.targetExecutorId,
      );
    }
    throw StateError('Unsupported edge data type: ${d.runtimeType}');
  }
}

/// Converts [RequestPortDescriptor] instances to their checkpoint
/// representation.
extension RequestPortDescriptorRepresentation on RequestPortDescriptor {
  /// Returns a [RequestPortInfo] describing this port.
  RequestPortInfo toPortInfo() => RequestPortInfo(
    id: id,
    requestType: requestType.toString(),
    responseType: responseType.toString(),
    description: description,
  );
}

/// Converts [Workflow] instances to their checkpoint representation.
extension WorkflowRepresentation on Workflow {
  /// Returns a [WorkflowInfo] describing this workflow.
  WorkflowInfo toWorkflowInfo() => WorkflowInfo.fromWorkflow(this);
}

/// Converts [CheckpointInfo] instances to string keys for use in maps.
extension CheckpointInfoKey on CheckpointInfo {
  /// Returns the string map key for this checkpoint.
  String toKey() => CheckpointInfoConverter().stringify(this);

  /// Parses a [CheckpointInfo] from its string map key.
  static CheckpointInfo fromKey(String key) =>
      CheckpointInfoConverter().parse(key);
}
