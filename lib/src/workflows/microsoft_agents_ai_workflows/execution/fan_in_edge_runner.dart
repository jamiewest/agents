import '../fan_in_edge_data.dart';
import 'message_envelope.dart';
import 'runner_state_data.dart';

/// Waits for every fan-in source before routing an aggregate message.
class FanInEdgeRunner {
  /// Creates a fan-in edge runner.
  const FanInEdgeRunner(this.edgeData);

  /// Gets the fan-in edge data.
  final FanInEdgeData edgeData;

  /// Records [message] from [sourceExecutorId] and routes once complete.
  MessageEnvelope? tryRoute(
    String sourceExecutorId,
    Object? message,
    RunnerStateData state,
  ) {
    if (!edgeData.sourceExecutorIds.contains(sourceExecutorId)) {
      return null;
    }
    final sourceMessages = state.fanInMessages.putIfAbsent(
      edgeData.id,
      () => <String, Object?>{},
    );
    sourceMessages[sourceExecutorId] = message;
    if (sourceMessages.length < edgeData.sourceExecutorIds.length) {
      return null;
    }
    final values = <Object?>[
      for (final source in edgeData.sourceExecutorIds) sourceMessages[source],
    ];
    sourceMessages.clear();
    return MessageEnvelope(
      sourceExecutorId: sourceExecutorId,
      targetExecutorId: edgeData.targetExecutorId,
      message: values,
    );
  }
}
