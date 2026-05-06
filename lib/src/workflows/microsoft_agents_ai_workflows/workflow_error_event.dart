import 'workflow_event.dart';

/// Event triggered when a workflow encounters an error.
///
/// [e] Optionally, the [Exception] representing the error.
class WorkflowErrorEvent extends WorkflowEvent {
  /// Event triggered when a workflow encounters an error.
  ///
  /// [e] Optionally, the [Exception] representing the error.
  WorkflowErrorEvent(Exception? e) : super(data: e);

  /// Gets the exception that caused the current operation to fail, if one
  /// occurred.
  Exception? get exception => data as Exception?;
}
