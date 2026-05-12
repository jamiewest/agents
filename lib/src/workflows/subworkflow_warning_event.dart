import 'workflow_warning_event.dart';

/// Event emitted when a subworkflow encounters a warning condition.
class SubworkflowWarningEvent extends WorkflowWarningEvent {
  /// Creates a [SubworkflowWarningEvent] for [subWorkflowId].
  SubworkflowWarningEvent(super.message, this.subWorkflowId);

  /// The unique identifier of the subworkflow that triggered the warning.
  final String subWorkflowId;
}
