import '../workflow_event.dart';

class ConcurrentEventSink implements EventSink {
  ConcurrentEventSink();

  void Function(ConcurrentEventSink, WorkflowEvent)? eventRaised;

  @override
  Future enqueue(WorkflowEvent workflowEvent) {
    eventRaised?.call(this, workflowEvent);
    return Future.value();
  }
}

abstract class EventSink {
  Future enqueue(WorkflowEvent workflowEvent);
}
