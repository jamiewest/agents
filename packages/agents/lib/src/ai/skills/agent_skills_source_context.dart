import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/ai_agent.dart';

/// Provides contextual information about the agent and session to an
/// `AgentSkillsSource` when retrieving skills.
class AgentSkillsSourceContext {
  /// Creates a context for the [agent] requesting skills and the [session]
  /// associated with the agent invocation, if any.
  AgentSkillsSourceContext(this.agent, this.session);

  /// The agent requesting skills.
  final AIAgent agent;

  /// The session associated with the agent invocation, if any.
  final AgentSession? session;
}
