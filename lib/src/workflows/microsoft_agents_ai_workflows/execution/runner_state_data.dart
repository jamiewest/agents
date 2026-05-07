import '../edge_id.dart';

/// Mutable state carried by an in-process workflow runner.
class RunnerStateData {
  /// Creates runner state data.
  RunnerStateData();

  /// Gets fan-in messages accumulated by edge and source executor.
  final Map<EdgeId, Map<String, Object?>> fanInMessages =
      <EdgeId, Map<String, Object?>>{};
}
