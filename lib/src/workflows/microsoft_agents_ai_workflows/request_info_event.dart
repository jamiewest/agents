import 'external_request.dart';
import 'workflow_event.dart';

/// Event triggered when a workflow executor request external information.
class RequestInfoEvent extends WorkflowEvent {
  /// Event triggered when a workflow executor request external information.
  RequestInfoEvent(ExternalRequest request)
      : request = request,
        super(data: request);

  /// The request to be serviced and data payload associated with it.
  final ExternalRequest request;
}
