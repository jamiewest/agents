import 'output_tag.dart';
import 'workflow_event.dart';

/// Event emitted when a workflow yields output.
class WorkflowOutputEvent extends WorkflowEvent {
  /// Creates a workflow-output event.
  ///
  /// [tags] associates output tags with this event; it is empty for
  /// terminal/regular outputs. The presence of [OutputTag.intermediate] marks
  /// this event as an intermediate output.
  const WorkflowOutputEvent({
    required this.executorId,
    super.data,
    this.tags = const <OutputTag>{},
  });

  /// Gets the source executor identifier.
  final String executorId;

  /// The set of output tags associated with this event. Never null; empty for
  /// terminal/regular outputs.
  final Set<OutputTag> tags;

  /// Returns `true` if this event carries the given [tag].
  bool hasTag(OutputTag tag) => tags.contains(tag);
}
