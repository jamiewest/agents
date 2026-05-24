import '../fan_out_edge_data.dart';
import 'message_envelope.dart';

/// Routes one source message to every fan-out target.
class FanOutEdgeRunner {
  /// Creates a fan-out edge runner.
  const FanOutEdgeRunner(this.edgeData);

  /// Gets the fan-out edge data.
  final FanOutEdgeData edgeData;

  /// Routes [message] from [sourceExecutorId].
  Iterable<MessageEnvelope> route(String sourceExecutorId, Object? message) {
    if (edgeData.sourceExecutorId != sourceExecutorId) {
      return const <MessageEnvelope>[];
    }
    return edgeData.targetExecutorIds.map(
      (targetExecutorId) => MessageEnvelope(
        sourceExecutorId: sourceExecutorId,
        targetExecutorId: targetExecutorId,
        message: message,
      ),
    );
  }
}
