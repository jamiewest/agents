import '../edge_id.dart';
import 'fan_in_edge_state.dart';

/// Mutable state carried by an in-process workflow runner.
class RunnerStateData {
  /// Creates runner state data.
  RunnerStateData();

  /// Gets fan-in buffering state keyed by edge.
  final Map<EdgeId, FanInEdgeState> fanInStates = <EdgeId, FanInEdgeState>{};
}
