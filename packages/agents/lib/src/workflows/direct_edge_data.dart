import 'edge_data.dart';
import 'edge_id.dart';

/// Edge data for a direct source-to-target connection.
class DirectEdgeData extends EdgeData {
  /// Creates direct edge data.
  const DirectEdgeData({
    required EdgeId id,
    required this.sourceExecutorId,
    required this.targetExecutorId,
    this.messageType,
  }) : super(id);

  /// Gets the source executor identifier.
  final String sourceExecutorId;

  /// Gets the target executor identifier.
  final String targetExecutorId;

  /// Gets the optional routed message type.
  final Type? messageType;

  @override
  Iterable<String> get sourceExecutorIds => <String>[sourceExecutorId];

  @override
  Iterable<String> get targetExecutorIds => <String>[targetExecutorId];
}
