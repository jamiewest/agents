import 'workflow_event.dart';

/// Event triggered when a workflow encounters a warning-condition.
///
/// [message] The warning message.
class WorkflowWarningEvent extends WorkflowEvent {
  /// Event triggered when a workflow encounters a warning-condition.
  ///
  /// [message] The warning message.
  WorkflowWarningEvent(String message);
}
