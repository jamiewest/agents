import '../../func_typedefs.dart';
import 'edge_data.dart';
import 'edge_id.dart';
import 'execution/edge_connection.dart';

/// Represents a connection from a single node to a set of nodes, optionally
/// associated with a paritition selector function which maps incoming
/// messages to a subset of the target set.
class FanOutEdgeData extends EdgeData {
  FanOutEdgeData(
    String sourceId,
    List<String> sinkIds,
    EdgeId edgeId,
    {Func2<Object?, int, Iterable<int>>? assigner = null, String? label = null, },
  ) :
      sourceId = sourceId,
      sinkIds = sinkIds {
    this.edgeAssigner = assigner;
    this.connection = new([sourceId], sinkIds);
  }

  /// The Id of the source [Executor] node.
  final String sourceId;

  /// The ordered list of Ids of the destination [Executor] nodes.
  final List<String> sinkIds;

  /// A function mapping an incoming message to a subset of the target executor
  /// nodes (or optionally all of them). If `null`, all destination nodes are
  /// selected.
  final Func2<Object?, int, Iterable<int>>? edgeAssigner;

  late final EdgeConnection connection;

}
