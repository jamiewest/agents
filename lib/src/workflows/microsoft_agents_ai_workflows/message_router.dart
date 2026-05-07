import 'direct_edge_data.dart';
import 'execution/direct_edge_runner.dart';
import 'execution/edge_map.dart';
import 'execution/fan_in_edge_runner.dart';
import 'execution/fan_out_edge_runner.dart';
import 'execution/message_envelope.dart';
import 'execution/runner_state_data.dart';
import 'fan_in_edge_data.dart';
import 'fan_out_edge_data.dart';

/// Routes executor outputs across workflow edges.
class MessageRouter {
  /// Creates a message router.
  const MessageRouter(this.edgeMap, this.state);

  /// Gets the edge map.
  final EdgeMap edgeMap;

  /// Gets mutable runner state used for fan-in routing.
  final RunnerStateData state;

  /// Routes [message] emitted by [sourceExecutorId].
  Iterable<MessageEnvelope> route(
    String sourceExecutorId,
    Object? message,
  ) sync* {
    for (final edge in edgeMap.getEdgesFrom(sourceExecutorId)) {
      final data = edge.data;
      if (data is DirectEdgeData) {
        final envelope = DirectEdgeRunner(
          data,
        ).tryRoute(sourceExecutorId, message);
        if (envelope != null) {
          yield envelope;
        }
      } else if (data is FanOutEdgeData) {
        yield* FanOutEdgeRunner(data).route(sourceExecutorId, message);
      } else if (data is FanInEdgeData) {
        final envelope = FanInEdgeRunner(
          data,
        ).tryRoute(sourceExecutorId, message, state);
        if (envelope != null) {
          yield envelope;
        }
      }
    }
  }
}
