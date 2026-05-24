import '../edge.dart';

/// Indexes workflow edges by their source executor identifiers.
class EdgeMap {
  /// Creates an edge map.
  EdgeMap(Iterable<Edge> edges) {
    for (final edge in edges) {
      _edges.add(edge);
      for (final sourceExecutorId in edge.sourceExecutorIds) {
        (_bySource[sourceExecutorId] ??= <Edge>[]).add(edge);
      }
    }
  }

  final List<Edge> _edges = <Edge>[];
  final Map<String, List<Edge>> _bySource = <String, List<Edge>>{};

  /// Gets all edges in insertion order.
  Iterable<Edge> get edges => _edges;

  /// Gets edges whose source includes [sourceExecutorId].
  Iterable<Edge> getEdgesFrom(String sourceExecutorId) =>
      _bySource[sourceExecutorId] ?? const <Edge>[];
}
