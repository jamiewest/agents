import 'workflow_warning_event.dart';

/// Event triggered when a subworkflow encounters a warning-confition.
/// sub-workflow.
///
/// [message] The warning message.
///
/// [subWorkflowId] The unique identifier of the sub-workflow that triggered
/// the warning. Cannot be null or empty.
class SubworkflowWarningEvent extends WorkflowWarningEvent {
  /// Event triggered when a subworkflow encounters a warning-confition.
  /// sub-workflow.
  ///
  /// [message] The warning message.
  ///
  /// [subWorkflowId] The unique identifier of the sub-workflow that triggered
  /// the warning. Cannot be null or empty.
  const SubworkflowWarningEvent(String message, String subWorkflowId)
    : subWorkflowId = subWorkflowId;

  /// The unique identifier of the sub-workflow that triggered the warning.
  final String subWorkflowId = subWorkflowId;
}
