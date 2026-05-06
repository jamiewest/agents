import '../edge.dart';
import '../edge_data.dart';
import '../execution/edge_connection.dart';
import '../fan_out_edge_data.dart';
import '../workflow.dart';
import 'edge_info.dart';

/// Represents a fan-out [Edge] in the [Workflow].
class FanOutEdgeInfo extends EdgeInfo {
  FanOutEdgeInfo({FanOutEdgeData? data, bool? hasAssigner, EdgeConnection? connection})
      : super(EdgeKind.fanOut, connection ?? EdgeConnection([], []));

  /// Gets a value indicating whether this fan-has an edge-assigner
  /// associated with it.
  late final bool hasAssigner;

  @override
  bool isMatchInternal(EdgeData edgeData) {
    return edgeData is FanOutEdgeData
            && this.hasAssigner == (edgeData.edgeAssigner != null);
  }
}
