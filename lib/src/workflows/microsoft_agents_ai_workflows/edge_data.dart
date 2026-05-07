import 'edge_id.dart';

/// Base data for a workflow edge.
abstract class EdgeData {
  /// Creates edge data.
  const EdgeData(this.id);

  /// Gets the edge identifier.
  final EdgeId id;

  /// Gets the source executor identifiers.
  Iterable<String> get sourceExecutorIds;

  /// Gets the target executor identifiers.
  Iterable<String> get targetExecutorIds;
}
