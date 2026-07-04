import 'package:extensions/system.dart';
import '../abstractions/ai_agent.dart';
import '../abstractions/agent_session.dart';

/// Defines the contract for storing and retrieving agent conversation
/// threads.
///
/// Implementations enable persistent storage of conversation threads,
/// allowing conversations to be resumed across HTTP requests, application
/// restarts, or different service instances in hosted scenarios.
///
/// **Trust model.** The `conversationId` passed to [getSession] and
/// [saveSession] typically originates from the wire. It is a chain-resume
/// identifier, *not* an authorization token, and the `(agent, conversationId)`
/// tuple carries no principal/owner dimension. Hosts that serve more than one
/// user from the same registered store must therefore compose a principal
/// dimension into the lookup key — otherwise any caller who knows or guesses
/// another caller's `conversationId` can resume that other caller's persisted
/// thread. The framework provides `IsolationKeyScopedAgentSessionStore` as a
/// decorator that rewrites `conversationId` to include an isolation key
/// resolved from a `SessionIsolationKeyProvider`.
///
/// **Implementer guidance.** Treat `conversationId` as opaque: do not parse
/// it, do not impose length or character-set constraints on it, and do not
/// assume it round-trips to the value the caller originally supplied
/// (decorators may rewrite it before forwarding).
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

  /// Asks the store for an object of the specified [serviceType].
  ///
  /// Allows retrieval of strongly-typed services that might be provided by
  /// the store, including itself or any stores it might be wrapping. This is
  /// particularly useful for inspecting delegation chains to verify that
  /// specific store implementations are present.
  Object? getService(Type serviceType, {Object? serviceKey}) {
    if (serviceKey == null && runtimeType == serviceType) {
      return this;
    }
    return null;
  }
}
