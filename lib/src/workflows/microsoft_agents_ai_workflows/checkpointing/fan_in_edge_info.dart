import '../edge.dart';
import '../execution/edge_connection.dart';
import '../fan_in_edge_data.dart';
import '../workflow.dart';
import 'edge_info.dart';

/// Represents a fan-in [Edge] in the [Workflow].
class FanInEdgeInfo extends EdgeInfo {
  FanInEdgeInfo({FanInEdgeData? data, EdgeConnection? connection})
      : super(EdgeKind.fanIn, connection ?? EdgeConnection([], []));
}
