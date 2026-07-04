import 'output_tag.dart';
import 'workflow_output_event.dart';

/// Extension helpers for inspecting [WorkflowOutputEvent] tag membership.
extension WorkflowOutputEventExtensions on WorkflowOutputEvent {
  /// Returns `true` if the event carries [OutputTag.intermediate] in its
  /// [WorkflowOutputEvent.tags].
  bool get isIntermediate => hasTag(OutputTag.intermediate);
}
