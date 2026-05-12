import 'edge_data.dart';
import 'edge_id.dart';

/// Edge data for a source executor connected to multiple targets.
class FanOutEdgeData extends EdgeData {
  /// Creates fan-out edge data.
  FanOutEdgeData({
    required EdgeId id,
    required this.sourceExecutorId,
    required Iterable<String> targetExecutorIds,
  }) : targetExecutorIds = List<String>.unmodifiable(targetExecutorIds),
       super(id);

  /// Gets the source executor identifier.
  final String sourceExecutorId;

  /// Gets the target executor identifiers.
  @override
  final List<String> targetExecutorIds;

  @override
  Iterable<String> get sourceExecutorIds => <String>[sourceExecutorId];
}
