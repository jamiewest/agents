import '../edge.dart';

/// Connects an edge to executable routing behavior.
class EdgeConnection {
  /// Creates an edge connection.
  const EdgeConnection(this.edge);

  /// Gets the workflow edge.
  final Edge edge;

  /// Gets the edge source executor identifiers.
  Iterable<String> get sourceExecutorIds => edge.sourceExecutorIds;

  /// Gets the edge target executor identifiers.
  Iterable<String> get targetExecutorIds => edge.targetExecutorIds;
}
