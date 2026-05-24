import '../abstractions/agent_response_update.dart';
import 'workflow_output_event.dart';

/// Workflow output event carrying an [AgentResponseUpdate].
class AgentResponseUpdateEvent extends WorkflowOutputEvent {
  /// Creates an agent response update event.
  const AgentResponseUpdateEvent({
    required super.executorId,
    required this.update,
  }) : super(data: update);

  /// Gets the agent response update.
  final AgentResponseUpdate update;
}
