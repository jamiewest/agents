import 'agent_session_state_bag.dart';
import 'chat_history_provider.dart';

/// Base abstraction for all agent threads.
///
/// Remarks: An [AgentSession] contains the state of a specific conversation
/// with an agent which may include conversation history, memories, and any
/// other state that the agent needs to persist across runs.
abstract class AgentSession {
  /// Initializes a new instance of the [AgentSession] class.
  AgentSession(this.stateBag);

  /// Gets any arbitrary state associated with this session.
  ///
  /// Remarks: Data stored in the [stateBag] will be included when the session
  /// is serialized. Avoid storing secrets or sensitive data without encryption.
  AgentSessionStateBag stateBag;

  /// Asks the [AgentSession] for an Object of the specified [serviceType].
  ///
  /// Returns the found Object, or `null` if not available.
  Object? getService(Type serviceType, {Object? serviceKey}) {
    return serviceKey == null && serviceType == runtimeType ? this : null;
  }
}
