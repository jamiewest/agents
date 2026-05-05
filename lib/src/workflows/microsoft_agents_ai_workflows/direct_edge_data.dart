import '../../func_typedefs.dart';
import 'edge_data.dart';
import 'edge_id.dart';
import 'execution/edge_connection.dart';

/// Represents a directed edge between two nodes, optionally associated with a
/// condition that determines whether the edge is active.
class DirectEdgeData extends EdgeData {
  DirectEdgeData(
    String sourceId,
    String sinkId,
    EdgeId id,
    {Func<Object?, bool>? condition = null, String? label = null, },
  ) :
      sourceId = sourceId,
      sinkId = sinkId {
    this.condition = condition;
    this.connection = new([sourceId], [sinkId]);
  }

  /// The Id of the source [Executor] node.
  final String sourceId;

  /// The Id of the destination [Executor] node.
  final String sinkId;

  /// An optional predicate determining whether the edge is active for a given
  /// message. If `null`, the edge is always active when a message is generated
  /// by the source.
  final Func<Object?, bool>? condition;

  late final EdgeConnection connection;

}
