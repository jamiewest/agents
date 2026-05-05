import '../workflow_event.dart';

class ConcurrentEventSink implements EventSink {
  ConcurrentEventSink();

  @override
  Future enqueue(WorkflowEvent workflowEvent) {
    return this.eventRaised?.invoke(this, workflowEvent) ?? default;
  }
}
abstract class EventSink {
  Future enqueue(WorkflowEvent workflowEvent);
}
