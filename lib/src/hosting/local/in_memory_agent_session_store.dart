import 'package:extensions/system.dart';

import '../../abstractions/ai_agent.dart';
import '../../abstractions/agent_session.dart';
import '../agent_session_store.dart';

/// In-memory implementation of [AgentSessionStore] for development and
/// testing scenarios.
///
/// Remarks: Stores sessions in a simple [Map]. All sessions are lost when the
/// process restarts. For production use, choose a durable store.
class InMemoryAgentSessionStore extends AgentSessionStore {
  InMemoryAgentSessionStore();

  final Map<String, dynamic> _threads = {};

  @override
  Future saveSession(
    AIAgent agent,
    String conversationId,
    AgentSession session, {
    CancellationToken? cancellationToken,
  }) async {
    final key = _key(conversationId, agent.id);
    _threads[key] = await agent.serializeSession(
      session,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<AgentSession> getSession(
    AIAgent agent,
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async {
    final key = _key(conversationId, agent.id);
    final existing = _threads[key];
    if (existing == null) {
      return agent.createSession(cancellationToken: cancellationToken);
    }
    return agent.deserializeSession(
      existing,
      cancellationToken: cancellationToken,
    );
  }

  static String _key(String conversationId, String agentId) =>
      '$agentId:$conversationId';
}
