import '../fan_in_edge_data.dart';
import 'fan_in_edge_state.dart';
import 'message_envelope.dart';
import 'runner_state_data.dart';

/// Waits for every fan-in source before routing an aggregate message.
class FanInEdgeRunner {
  /// Creates a fan-in edge runner.
  const FanInEdgeRunner(this.edgeData);

  /// Gets the fan-in edge data.
  final FanInEdgeData edgeData;

  /// Records [message] from [sourceExecutorId] and routes once complete.
  ///
  /// Buffered messages persist in [state] until every source has
  /// contributed at least once; the released envelope carries a
  /// `List<Object?>` of all buffered payloads ordered by source (in
  /// [FanInEdgeData.sourceExecutorIds] order), then arrival.
  MessageEnvelope? tryRoute(
    String sourceExecutorId,
    Object? message,
    RunnerStateData state,
  ) {
    if (!edgeData.sourceExecutorIds.contains(sourceExecutorId)) {
      return null;
    }
    final edgeState = state.fanInStates.putIfAbsent(
      edgeData.id,
      () => FanInEdgeState(edgeData),
    );
    final grouped = edgeState.processMessage(
      sourceExecutorId,
      MessageEnvelope(
        sourceExecutorId: sourceExecutorId,
        targetExecutorId: edgeData.targetExecutorId,
        message: message,
      ),
    );
    if (grouped == null) {
      return null;
    }
    final values = <Object?>[
      for (final source in edgeData.sourceExecutorIds)
        for (final envelope in grouped[source] ?? const <MessageEnvelope>[])
          envelope.message,
    ];
    return MessageEnvelope(
      sourceExecutorId: sourceExecutorId,
      targetExecutorId: edgeData.targetExecutorId,
      message: values,
    );
  }
}
