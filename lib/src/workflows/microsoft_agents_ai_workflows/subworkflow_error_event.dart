import 'workflow_error_event.dart';

/// Event emitted when a subworkflow encounters an error.
class SubworkflowErrorEvent extends WorkflowErrorEvent {
  /// Creates a [SubworkflowErrorEvent] for [subworkflowId].
  SubworkflowErrorEvent(this.subworkflowId, Object error) : super(error);

  /// The ID of the subworkflow that encountered the error.
  final String subworkflowId;
}
