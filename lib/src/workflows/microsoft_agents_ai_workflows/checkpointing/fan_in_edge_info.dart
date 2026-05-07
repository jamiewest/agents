import 'edge_info.dart';

/// Serializable fan-in edge information.
class FanInEdgeInfo extends EdgeInfo {
  /// Creates fan-in edge info.
  FanInEdgeInfo({
    required super.edgeId,
    required Iterable<String> sourceExecutorIds,
    required this.targetExecutorId,
  }) : sourceExecutorIds = List<String>.unmodifiable(sourceExecutorIds),
       super(kind: 'fanIn');

  /// Gets source executor identifiers.
  @override
  final List<String> sourceExecutorIds;

  /// Gets the target executor identifier.
  final String targetExecutorId;

  @override
  Iterable<String> get targetExecutorIds => <String>[targetExecutorId];

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'edgeId': edgeId,
    'sourceExecutorIds': sourceExecutorIds,
    'targetExecutorId': targetExecutorId,
  };

  /// Creates fan-in edge info from JSON.
  factory FanInEdgeInfo.fromJson(Map<String, Object?> json) => FanInEdgeInfo(
    edgeId: json['edgeId']! as String,
    sourceExecutorIds: checkpointStringList(json['sourceExecutorIds']),
    targetExecutorId: json['targetExecutorId']! as String,
  );
}
