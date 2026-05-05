import 'direct_edge_data.dart';
import 'edge_data.dart';
import 'fan_in_edge_data.dart';
import 'fan_out_edge_data.dart';

/// Represents a connection or relationship between nodes, characterized by
/// its type and associated data.
///
/// Remarks: An [Edge] can be of type [Direct], [FanOut], or [FanIn], as
/// specified by the [Kind] property. The [Data] property holds additional
/// information relevant to the edge, and its concrete type depends on the
/// value of [Kind], functioning as a tagged union.
class Edge {
  Edge({DirectEdgeData? data = null}) {
    this.data = data;
    this.kind = EdgeKind.direct;
  }

  /// Specifies the type of the edge, which determines how the edge is processed
  /// in the workflow.
  late EdgeKind kind;

  /// The [EdgeKind]-dependent edge data.
  late EdgeData data;

  DirectEdgeData? get directEdgeData {
    return this.data as directEdgeData;
  }

  FanOutEdgeData? get fanOutEdgeData {
    return this.data as fanOutEdgeData;
  }

  FanInEdgeData? get fanInEdgeData {
    return this.data as fanInEdgeData;
  }
}

/// Specified the edge type.
enum EdgeKind {
  /// A direct connection from one node to another.
  direct,

  /// A connection from one node to a set of nodes.
  fanOut,

  /// A connection from a set of nodes to a single node.
  fanIn,
}
