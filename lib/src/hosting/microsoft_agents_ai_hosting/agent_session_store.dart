import 'package:extensions/system.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';

/// Defines the contract for storing and retrieving agent conversation
/// threads.
///
/// Remarks: Implementations of this interface enable persistent storage of
/// conversation threads, allowing conversations to be resumed across HTTP
/// requests, application restarts, or different service instances in hosted
/// scenarios.
abstract class AgentSessionStore {
  AgentSessionStore();

  /// Saves a serialized agent session to persistent storage.
  ///
  /// Returns: A task that represents the asynchronous save operation.
  ///
  /// [agent] The agent that owns this session.
  ///
  /// [conversationId] The unique identifier for the conversation/session.
  ///
  /// [session] The session to save.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests.
  Future saveSession(
    AIAgent agent,
    String conversationId,
    AgentSession session, {
    CancellationToken? cancellationToken,
  });

  /// Retrieves a serialized agent session from persistent storage.
  ///
  /// Returns: A task that represents the asynchronous retrieval operation. The
  /// task result contains the serialized session state, or `null` if not found.
  ///
  /// [agent] The agent that owns this session.
  ///
  /// [conversationId] The unique identifier for the conversation/session to
  /// retrieve.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests.
  Future<AgentSession> getSession(
    AIAgent agent,
    String conversationId, {
    CancellationToken? cancellationToken,
  });
}
