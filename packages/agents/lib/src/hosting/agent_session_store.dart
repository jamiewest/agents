import 'package:extensions/system.dart';
import '../abstractions/ai_agent.dart';
import '../abstractions/agent_session.dart';

/// Defines the contract for storing and retrieving agent conversation
/// threads.
///
/// Implementations enable persistent storage of conversation threads,
/// allowing conversations to be resumed across HTTP requests, application
/// restarts, or different service instances in hosted scenarios.
abstract class AgentSessionStore {
  AgentSessionStore();

  /// Saves [session] for [conversationId] to persistent storage.
  Future saveSession(
    AIAgent agent,
    String conversationId,
    AgentSession session, {
    CancellationToken? cancellationToken,
  });

  /// Retrieves the session for [conversationId] from persistent storage.
  ///
  /// Returns the deserialized session, or a newly created session if none is
  /// found.
  Future<AgentSession> getSession(
    AIAgent agent,
    String conversationId, {
    CancellationToken? cancellationToken,
  });
}
