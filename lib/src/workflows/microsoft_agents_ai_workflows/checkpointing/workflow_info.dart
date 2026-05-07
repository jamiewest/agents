import 'direct_edge_info.dart';
import 'edge_info.dart';
import 'executor_info.dart';
import 'fan_in_edge_info.dart';
import 'fan_out_edge_info.dart';
import '../direct_edge_data.dart';
import '../fan_in_edge_data.dart';
import '../fan_out_edge_data.dart';
import '../workflow.dart';

/// Serializable workflow definition information.
class WorkflowInfo {
  /// Creates workflow info.
  WorkflowInfo({
    required this.startExecutorId,
    Iterable<ExecutorInfo> executors = const <ExecutorInfo>[],
    Iterable<EdgeInfo> edges = const <EdgeInfo>[],
    Iterable<String> outputExecutorIds = const <String>[],
    this.name,
    this.description,
  }) : executors = List<ExecutorInfo>.unmodifiable(executors),
       edges = List<EdgeInfo>.unmodifiable(edges),
       outputExecutorIds = List<String>.unmodifiable(outputExecutorIds);

  /// Gets the start executor identifier.
  final String startExecutorId;

  /// Gets the workflow name.
  final String? name;

  /// Gets the workflow description.
  final String? description;

  /// Gets executor infos.
  final List<ExecutorInfo> executors;

  /// Gets edge infos.
  final List<EdgeInfo> edges;

  /// Gets output executor identifiers.
  final List<String> outputExecutorIds;

  /// Converts this workflow info to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'startExecutorId': startExecutorId,
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    'executors': executors.map((executor) => executor.toJson()).toList(),
    'edges': edges.map((edge) => edge.toJson()).toList(),
    'outputExecutorIds': outputExecutorIds,
  };

  /// Creates workflow info from JSON.
  factory WorkflowInfo.fromJson(Map<String, Object?> json) => WorkflowInfo(
    startExecutorId: json['startExecutorId']! as String,
    name: json['name'] as String?,
    description: json['description'] as String?,
    executors: (json['executors'] as List? ?? const <Object?>[])
        .cast<Map>()
        .map((value) => ExecutorInfo.fromJson(value.cast<String, Object?>())),
    edges: (json['edges'] as List? ?? const <Object?>[]).cast<Map>().map(
      (value) => EdgeInfo.fromJson(value.cast<String, Object?>()),
    ),
    outputExecutorIds: checkpointStringList(json['outputExecutorIds']),
  );

  /// Creates workflow info from a runtime [workflow].
  factory WorkflowInfo.fromWorkflow(Workflow workflow) => WorkflowInfo(
    startExecutorId: workflow.startExecutorId,
    name: workflow.name,
    description: workflow.description,
    executors: workflow.reflectExecutors().map(
      (binding) => ExecutorInfo(
        executorId: binding.id,
        supportsConcurrentSharedExecution:
            binding.supportsConcurrentSharedExecution,
        supportsResetting: binding.supportsResetting,
      ),
    ),
    edges: workflow.reflectEdges().map((edge) {
      final data = edge.data;
      if (data is DirectEdgeData) {
        return DirectEdgeInfo(
          edgeId: data.id.value,
          sourceExecutorId: data.sourceExecutorId,
          targetExecutorId: data.targetExecutorId,
          messageType: data.messageType?.toString(),
        );
      }
      if (data is FanOutEdgeData) {
        return FanOutEdgeInfo(
          edgeId: data.id.value,
          sourceExecutorId: data.sourceExecutorId,
          targetExecutorIds: data.targetExecutorIds,
        );
      }
      if (data is FanInEdgeData) {
        return FanInEdgeInfo(
          edgeId: data.id.value,
          sourceExecutorIds: data.sourceExecutorIds,
          targetExecutorId: data.targetExecutorId,
        );
      }
      throw StateError('Unsupported edge data type ${data.runtimeType}.');
    }),
    outputExecutorIds: workflow.reflectOutputExecutors(),
  );
}
