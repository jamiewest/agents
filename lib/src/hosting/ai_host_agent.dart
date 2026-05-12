import 'package:extensions/system.dart';

import '../abstractions/ai_agent.dart';
import '../abstractions/agent_session.dart';
import '../abstractions/delegating_ai_agent.dart';
import 'agent_session_store.dart';

/// Provides a hosting wrapper around an [AIAgent] that adds session
/// persistence capabilities for server-hosted scenarios.
///
/// Remarks: [AIHostAgent] wraps an existing agent and adds the ability to
/// persist and restore conversation threads using an [AgentSessionStore].
class AIHostAgent extends DelegatingAIAgent {
  /// Creates an [AIHostAgent] wrapping [innerAgent] with [sessionStore].
  AIHostAgent(super.innerAgent, this._sessionStore);

  final AgentSessionStore _sessionStore;

  /// Gets an existing session for [conversationId], or creates one.
  Future<AgentSession> getOrCreateSession(
    String conversationId, {
    CancellationToken? cancellationToken,
  }) {
    return _sessionStore.getSession(
      innerAgent,
      conversationId,
      cancellationToken: cancellationToken,
    );
  }

  /// Persists [session] for [conversationId].
  Future saveSession(
    String conversationId,
    AgentSession session, {
    CancellationToken? cancellationToken,
  }) {
    return _sessionStore.saveSession(
      innerAgent,
      conversationId,
      session,
      cancellationToken: cancellationToken,
    );
  }
}
