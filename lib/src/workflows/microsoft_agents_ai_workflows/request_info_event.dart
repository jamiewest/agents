import 'external_request.dart';
import 'workflow_event.dart';

/// Event triggered when a workflow executor request external information.
class RequestInfoEvent extends WorkflowEvent {
  /// Event triggered when a workflow executor request external information.
  const RequestInfoEvent(ExternalRequest request) : request = request;

  /// The request to be serviced and data payload associated with it.
  ExternalRequest get request {
    return request;
  }
}
