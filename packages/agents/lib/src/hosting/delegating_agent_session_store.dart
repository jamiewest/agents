import 'package:extensions/system.dart';

import '../abstractions/agent_session.dart';
import '../abstractions/ai_agent.dart';
import 'agent_session_store.dart';

/// Provides an abstract base class for agent session stores that delegate
/// operations to an inner store instance while allowing for extensibility and
/// customization.
///
/// [DelegatingAgentSessionStore] implements the decorator pattern for
/// [AgentSessionStore]s, enabling the creation of pipelines where each layer
/// can add functionality while delegating core operations to an underlying
/// store.
///
/// The default implementation provides transparent pass-through behavior,
/// forwarding all operations to the inner store. Derived classes can override
/// specific methods to add custom behavior while maintaining compatibility
/// with the store interface.
abstract class DelegatingAgentSessionStore extends AgentSessionStore {
  /// Creates a [DelegatingAgentSessionStore] wrapping [innerStore].
  DelegatingAgentSessionStore(this.innerStore);

  /// Gets the inner session store instance that receives delegated
  /// operations.
  final AgentSessionStore innerStore;

  @override
  Future<AgentSession> getSession(
    AIAgent agent,
    String conversationId, {
    CancellationToken? cancellationToken,
  }) => innerStore.getSession(
    agent,
    conversationId,
    cancellationToken: cancellationToken,
  );

  @override
  Future saveSession(
    AIAgent agent,
    String conversationId,
    AgentSession session, {
    CancellationToken? cancellationToken,
  }) => innerStore.saveSession(
    agent,
    conversationId,
    session,
    cancellationToken: cancellationToken,
  );

  /// First checks if this instance satisfies the service request; if not,
  /// chains the request to the inner store, allowing services to be
  /// retrieved from any store in the delegation chain.
  @override
  Object? getService(Type serviceType, {Object? serviceKey}) =>
      super.getService(serviceType, serviceKey: serviceKey) ??
      innerStore.getService(serviceType, serviceKey: serviceKey);
}
