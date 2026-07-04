import 'direct_edge_info.dart';
import 'edge_info.dart';
import 'executor_info.dart';
import 'fan_in_edge_info.dart';
import 'fan_out_edge_info.dart';
import 'workflow_info_output_executors_converter.dart';
import '../direct_edge_data.dart';
import '../fan_in_edge_data.dart';
import '../fan_out_edge_data.dart';
import '../output_tag.dart';
import '../workflow.dart';

/// Serializable workflow definition information.
class WorkflowInfo {
  /// Creates workflow info.
  ///
  /// Output executors may be given as plain [outputExecutorIds] (untagged)
  /// or as an [outputExecutors] map with per-executor [OutputTag]s; the two
  /// are merged.
  WorkflowInfo({
    required this.startExecutorId,
    Iterable<ExecutorInfo> executors = const <ExecutorInfo>[],
    Iterable<EdgeInfo> edges = const <EdgeInfo>[],
    Iterable<String> outputExecutorIds = const <String>[],
    Map<String, Set<OutputTag>> outputExecutors =
        const <String, Set<OutputTag>>{},
    this.name,
    this.description,
  }) : executors = List<ExecutorInfo>.unmodifiable(executors),
       edges = List<EdgeInfo>.unmodifiable(edges),
       outputExecutors = Map<String, Set<OutputTag>>.unmodifiable({
         for (final executorId in outputExecutorIds)
           executorId: const <OutputTag>{},
         for (final entry in outputExecutors.entries)
           entry.key: Set<OutputTag>.unmodifiable(entry.value),
       });

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

  /// Gets output executor identifiers with their associated [OutputTag]s.
  final Map<String, Set<OutputTag>> outputExecutors;

  /// Gets output executor identifiers.
  List<String> get outputExecutorIds =>
      List<String>.unmodifiable(outputExecutors.keys);

  /// Converts this workflow info to JSON. Output executors are written in
  /// the tagged map shape (see [WorkflowInfoOutputExecutorsConverter]).
  Map<String, Object?> toJson() => <String, Object?>{
    'startExecutorId': startExecutorId,
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    'executors': executors.map((executor) => executor.toJson()).toList(),
    'edges': edges.map((edge) => edge.toJson()).toList(),
    'outputExecutorIds': WorkflowInfoOutputExecutorsConverter.encode(
      outputExecutors,
    ),
  };

  /// Creates workflow info from JSON. Accepts both the tagged map shape and
  /// the legacy string-array shape for `outputExecutorIds`.
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
    outputExecutors: WorkflowInfoOutputExecutorsConverter.decode(
      json['outputExecutorIds'],
    ),
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
    outputExecutors: workflow.reflectOutputExecutorTags(),
  );
}
