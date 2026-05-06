import '../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response_extensions.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import 'workflow_output_event.dart';

/// Represents an event triggered when an agent run produces an update.
class AgentResponseUpdateEvent extends WorkflowOutputEvent {
  /// Initializes a new instance of the [AgentResponseUpdateEvent] class.
  ///
  /// [executorId] The identifier of the executor that generated this event.
  ///
  /// [update] The agent run response update.
  AgentResponseUpdateEvent(String executorId, AgentResponseUpdate update)
    : update = update,
      super(update, executorId) {
  }

  /// Gets the agent run response update.
  final AgentResponseUpdate update;

  /// Converts this event to an [AgentResponse] containing just this update.
  ///
  /// Returns:
  AgentResponse asResponse() {
    var updates = [this.update];
    return updates.toAgentResponse();
  }
}
