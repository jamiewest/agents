import 'agent_run_mode.dart';

/// Options for configuring A2A server registration.
class A2AServerRegistrationOptions {
  /// The run mode that controls how the agent responds to A2A requests.
  ///
  /// When `null`, defaults to [AgentRunMode.disallowBackground].
  AgentRunMode? agentRunMode;
}
