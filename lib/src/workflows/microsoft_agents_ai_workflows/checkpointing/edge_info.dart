import '../edge.dart';
import '../edge_data.dart';
import '../execution/edge_connection.dart';

/// Base class representing information about an edge in a workflow.
class EdgeInfo {
  EdgeInfo(EdgeKind kind, EdgeConnection connection)
    : kind = kind,
      connection = connection {
  }

  /// The kind of edge.
  final EdgeKind kind;

  /// Gets the connection information associated with the edge.
  final EdgeConnection connection;

  bool isMatch(Edge edge) {
    return this.kind == edge.kind &&
        this.connection == edge.data.connection &&
        this.isMatchInternal(edge.data);
  }

  bool isMatchInternal(EdgeData edgeData) {
    return true;
  }
}
