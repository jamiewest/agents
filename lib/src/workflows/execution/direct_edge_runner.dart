import '../direct_edge_data.dart';
import 'message_envelope.dart';

/// Routes a message across a direct edge.
class DirectEdgeRunner {
  /// Creates a direct edge runner.
  const DirectEdgeRunner(this.edgeData);

  /// Gets the direct edge data.
  final DirectEdgeData edgeData;

  /// Attempts to route [message] from [sourceExecutorId].
  MessageEnvelope? tryRoute(String sourceExecutorId, Object? message) {
    if (edgeData.sourceExecutorId != sourceExecutorId) {
      return null;
    }
    final messageType = edgeData.messageType;
    if (messageType != null &&
        message != null &&
        message.runtimeType != messageType) {
      return null;
    }
    return MessageEnvelope(
      sourceExecutorId: sourceExecutorId,
      targetExecutorId: edgeData.targetExecutorId,
      message: message,
    );
  }
}
