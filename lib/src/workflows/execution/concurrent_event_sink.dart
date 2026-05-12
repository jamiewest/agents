import '../workflow_event.dart';

/// Receives workflow events and dispatches them to registered listeners.
abstract interface class IEventSink {
  /// Enqueues [workflowEvent] for delivery.
  Future<void> enqueue(WorkflowEvent workflowEvent);
}

/// An [IEventSink] that forwards events synchronously to a callback.
class ConcurrentEventSink implements IEventSink {
  /// Optional callback invoked for each enqueued [WorkflowEvent].
  Future<void> Function(Object? sender, WorkflowEvent event)? eventRaised;

  @override
  Future<void> enqueue(WorkflowEvent workflowEvent) =>
      eventRaised?.call(this, workflowEvent) ?? Future.value();
}
