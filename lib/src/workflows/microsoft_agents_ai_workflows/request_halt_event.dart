import 'workflow_event.dart';

/// Event triggered when a workflow completes execution.
class RequestHaltEvent extends WorkflowEvent {
  RequestHaltEvent({Object? result = null});
}
