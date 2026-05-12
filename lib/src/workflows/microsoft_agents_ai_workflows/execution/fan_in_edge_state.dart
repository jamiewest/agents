import '../execution/executor_identity.dart';
import '../fan_in_edge_data.dart';
import 'message_envelope.dart';

/// Accumulates messages from multiple fan-in sources, releasing all of them
/// as a grouped batch once every source has contributed.
///
/// Dart is single-threaded, so no locking is needed.
final class FanInEdgeState {
  /// Creates a [FanInEdgeState] from [fanInEdge].
  FanInEdgeState(FanInEdgeData fanInEdge)
    : sourceIds = List<String>.unmodifiable(fanInEdge.sourceExecutorIds),
      _unseen = Set<String>.of(fanInEdge.sourceExecutorIds),
      _pending = [];

  /// All expected source executor IDs.
  final List<String> sourceIds;

  final Set<String> _unseen;
  final List<MessageEnvelope> _pending;

  /// Records [envelope] from [sourceId].
  ///
  /// Returns an iterable of grouped [MessageEnvelope]s (one per distinct
  /// [ExecutorIdentity] source) when all sources have contributed, or `null`
  /// if more messages are still expected.
  Map<String, List<MessageEnvelope>>? processMessage(
    String sourceId,
    MessageEnvelope envelope,
  ) {
    _pending.add(envelope);
    _unseen.remove(sourceId);

    if (_unseen.isNotEmpty) return null;

    final taken = List<MessageEnvelope>.of(_pending);
    _pending.clear();
    _unseen.addAll(sourceIds);

    final grouped = <String, List<MessageEnvelope>>{};
    for (final msg in taken) {
      final key = msg.sourceExecutorId ?? '';
      (grouped[key] ??= []).add(msg);
    }
    return grouped;
  }
}
