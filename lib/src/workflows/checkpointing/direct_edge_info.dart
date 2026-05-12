import 'edge_info.dart';

/// Serializable direct edge information.
class DirectEdgeInfo extends EdgeInfo {
  /// Creates direct edge info.
  const DirectEdgeInfo({
    required super.edgeId,
    required this.sourceExecutorId,
    required this.targetExecutorId,
    this.messageType,
  }) : super(kind: 'direct');

  /// Gets the source executor identifier.
  final String sourceExecutorId;

  /// Gets the target executor identifier.
  final String targetExecutorId;

  /// Gets the routed message type name, when available.
  final String? messageType;

  @override
  Iterable<String> get sourceExecutorIds => <String>[sourceExecutorId];

  @override
  Iterable<String> get targetExecutorIds => <String>[targetExecutorId];

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'edgeId': edgeId,
    'sourceExecutorId': sourceExecutorId,
    'targetExecutorId': targetExecutorId,
    if (messageType != null) 'messageType': messageType,
  };

  /// Creates direct edge info from JSON.
  factory DirectEdgeInfo.fromJson(Map<String, Object?> json) => DirectEdgeInfo(
    edgeId: json['edgeId']! as String,
    sourceExecutorId: json['sourceExecutorId']! as String,
    targetExecutorId: json['targetExecutorId']! as String,
    messageType: json['messageType'] as String?,
  );
}
