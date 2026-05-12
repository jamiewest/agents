import 'package:extensions/system.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import 'agent_session_store.dart';

/// This store implementation does not have any store under the hood and
/// therefore does not store sessions. [CancellationToken)] always returns a
/// new session.
class NoopAgentSessionStore extends AgentSessionStore {
  NoopAgentSessionStore();

  @override
  Future saveSession(
    AIAgent agent,
    String conversationId,
    AgentSession session, {
    CancellationToken? cancellationToken,
  }) {
    return Future.value();
  }

  @override
  Future<AgentSession> getSession(
    AIAgent agent,
    String conversationId, {
    CancellationToken? cancellationToken,
  }) {
    return agent.createSession(cancellationToken: cancellationToken);
  }
}
