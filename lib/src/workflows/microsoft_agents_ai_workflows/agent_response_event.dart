import '../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import 'workflow_output_event.dart';

/// Represents an event triggered when an agent produces a response.
class AgentResponseEvent extends WorkflowOutputEvent {
  /// Initializes a new instance of the [AgentResponseEvent] class.
  ///
  /// [executorId] The identifier of the executor that generated this event.
  ///
  /// [response] The agent response.
  AgentResponseEvent(String executorId, AgentResponse response)
    : response = response,
      super(response, executorId) {
  }

  /// Gets the agent response.
  final AgentResponse response;
}
