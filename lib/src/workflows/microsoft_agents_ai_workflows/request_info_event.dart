import 'external_request.dart';
import 'workflow_event.dart';

/// Event triggered when a workflow executor requests external information.
class RequestInfoEvent extends WorkflowEvent {
  /// Creates a request-info event.
  const RequestInfoEvent(this.request) : super(data: request);

  /// Gets the request to be serviced.
  final ExternalRequest<dynamic, dynamic> request;
}
