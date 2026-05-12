import '../workflow_event.dart';
import 'concurrent_event_sink.dart';

/// Abstract base for [WorkflowEvent] event streams.
///
/// Extends [IEventSink] so implementations can be passed directly to
/// [InProcessRunner.topLevel] as the outgoing event destination, letting events
/// produced during execution flow immediately into the stream.
abstract class RunEventStream implements IEventSink {
  /// The stream of [WorkflowEvent]s produced by the workflow.
  Stream<WorkflowEvent> get events;

  /// Whether this stream has been completed and closed.
  bool get isCompleted;

  /// Marks the stream as completed and closes the underlying event source.
  Future<void> completeAsync();
}
