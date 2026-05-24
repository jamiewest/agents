import 'edge_info.dart';

/// Serializable fan-out edge information.
class FanOutEdgeInfo extends EdgeInfo {
  /// Creates fan-out edge info.
  FanOutEdgeInfo({
    required super.edgeId,
    required this.sourceExecutorId,
    required Iterable<String> targetExecutorIds,
  }) : targetExecutorIds = List<String>.unmodifiable(targetExecutorIds),
       super(kind: 'fanOut');

  /// Gets the source executor identifier.
  final String sourceExecutorId;

  /// Gets target executor identifiers.
  @override
  final List<String> targetExecutorIds;

  @override
  Iterable<String> get sourceExecutorIds => <String>[sourceExecutorId];

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'edgeId': edgeId,
    'sourceExecutorId': sourceExecutorId,
    'targetExecutorIds': targetExecutorIds,
  };

  /// Creates fan-out edge info from JSON.
  factory FanOutEdgeInfo.fromJson(Map<String, Object?> json) => FanOutEdgeInfo(
    edgeId: json['edgeId']! as String,
    sourceExecutorId: json['sourceExecutorId']! as String,
    targetExecutorIds: checkpointStringList(json['targetExecutorIds']),
  );
}
