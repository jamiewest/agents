import 'edge_data.dart';
import 'edge_id.dart';
import 'execution/edge_connection.dart';

/// Represents a connection from a set of nodes to a single node. It will
/// trigger either when all edges have data.
class FanInEdgeData extends EdgeData {
  FanInEdgeData(
    List<String> sourceIds,
    String sinkId,
    EdgeId id,
    String? label,
  ) :
      sourceIds = sourceIds,
      sinkId = sinkId,
      super(id, label: label) {
    this.connection = EdgeConnection(sourceIds, [sinkId]);
  }

  /// The ordered list of Ids of the source [Executor] nodes.
  final List<String> sourceIds;

  /// The Id of the destination [Executor] node.
  final String sinkId;

  late final EdgeConnection connection;

}
