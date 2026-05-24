import 'edge_data.dart';
import 'edge_id.dart';

/// Edge data for multiple source executors synchronized into one target.
class FanInEdgeData extends EdgeData {
  /// Creates fan-in edge data.
  FanInEdgeData({
    required EdgeId id,
    required Iterable<String> sourceExecutorIds,
    required this.targetExecutorId,
  }) : sourceExecutorIds = List<String>.unmodifiable(sourceExecutorIds),
       super(id);

  /// Gets the source executor identifiers.
  @override
  final List<String> sourceExecutorIds;

  /// Gets the target executor identifier.
  final String targetExecutorId;

  @override
  Iterable<String> get targetExecutorIds => <String>[targetExecutorId];
}
