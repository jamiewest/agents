import '../direct_edge_data.dart';
import '../edge.dart';
import '../edge_data.dart';
import '../execution/edge_connection.dart';
import '../workflow.dart';
import 'edge_info.dart';

/// Represents a direct [Edge] in the [Workflow].
class DirectEdgeInfo extends EdgeInfo {
  DirectEdgeInfo({DirectEdgeData? data, bool? hasCondition, EdgeConnection? connection})
      : super(EdgeKind.direct, connection ?? EdgeConnection([], []));

  /// Gets a value indicating whether this direct edge has a condition
  /// associated with it.
  late final bool hasCondition;

  @override
  bool isMatchInternal(EdgeData edgeData) {
    return edgeData is DirectEdgeData
            && this.hasCondition == (edgeData.condition != null);
  }
}
