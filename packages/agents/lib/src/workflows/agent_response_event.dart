import '../abstractions/agent_response.dart';
import 'workflow_output_event.dart';

/// Workflow output event carrying an [AgentResponse].
class AgentResponseEvent extends WorkflowOutputEvent {
  /// Creates an agent response event.
  const AgentResponseEvent({required super.executorId, required this.response})
    : super(data: response);

  /// Gets the agent response.
  final AgentResponse response;
}
