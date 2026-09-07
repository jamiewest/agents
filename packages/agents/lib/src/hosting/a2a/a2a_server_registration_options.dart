import 'agent_run_mode.dart';

/// Options for configuring A2A server registration.
class A2AServerRegistrationOptions {
  /// The run mode that controls which A2A artifact the agent responds with.
  ///
  /// When `null`, defaults to [AgentRunMode.returnMessage].
  AgentRunMode? agentRunMode;
}
