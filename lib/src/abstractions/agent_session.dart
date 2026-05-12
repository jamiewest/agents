import 'agent_session_state_bag.dart';

/// Base abstraction for all agent threads.
///
/// An [AgentSession] contains the state of a specific conversation with an
/// agent, which may include conversation history, memories, and any other
/// state that the agent needs to persist across runs.
abstract class AgentSession {
  /// Creates an [AgentSession] with the given [stateBag].
  AgentSession(this.stateBag);

  /// Arbitrary state associated with this session.
  ///
  /// Data stored here is included when the session is serialized. Avoid
  /// storing secrets or sensitive data without encryption.
  AgentSessionStateBag stateBag;

  /// Returns a service of the specified [serviceType], or `null`.
  Object? getService(Type serviceType, {Object? serviceKey}) {
    return serviceKey == null && serviceType == runtimeType ? this : null;
  }
}
