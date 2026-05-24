import 'package:extensions/system.dart';
import '../abstractions/ai_agent.dart';
import '../abstractions/agent_session.dart';
import 'agent_session_store.dart';

/// An [AgentSessionStore] that does not persist sessions.
///
/// Every call to [getSession] creates a new session; [saveSession] is a no-op.
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
