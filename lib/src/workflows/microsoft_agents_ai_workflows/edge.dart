import 'edge_data.dart';
import 'edge_id.dart';

/// Represents a workflow edge.
class Edge {
  /// Creates an edge.
  const Edge(this.data);

  /// Gets the edge data.
  final EdgeData data;

  /// Gets the edge identifier.
  EdgeId get id => data.id;

  /// Gets the source executor identifiers.
  Iterable<String> get sourceExecutorIds => data.sourceExecutorIds;

  /// Gets the target executor identifiers.
  Iterable<String> get targetExecutorIds => data.targetExecutorIds;
}
