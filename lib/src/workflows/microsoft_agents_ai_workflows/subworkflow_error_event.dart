import 'workflow_error_event.dart';

/// Event triggered when a workflow encounters an error.
///
/// [subworkflowId] The ID of the subworkflow that encountered the error.
///
/// [e] Optionally, the [Exception] representing the error.
class SubworkflowErrorEvent extends WorkflowErrorEvent {
  /// Event triggered when a workflow encounters an error.
  ///
  /// [subworkflowId] The ID of the subworkflow that encountered the error.
  ///
  /// [e] Optionally, the [Exception] representing the error.
  SubworkflowErrorEvent(String subworkflowId, Exception? e)
    : subworkflowId = subworkflowId,
      super(e);

  /// Gets the ID of the subworkflow that encountered the error.
  final String subworkflowId;
}
