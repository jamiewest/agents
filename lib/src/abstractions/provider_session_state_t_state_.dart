import 'agent_session.dart';
import 'agent_session_state_bag.dart';

/// Provides strongly-typed state management for providers, enabling reading
/// and writing of provider-specific state to/from an [AgentSession]'s
/// [AgentSessionStateBag].
///
/// [TState] The type of the state to be maintained.
class ProviderSessionState<TState> {
  /// Creates a [ProviderSessionState] with the given [stateInitializer] and
  /// [stateKey].
  // ignore_for_file: non_constant_identifier_names
  ProviderSessionState(this._stateInitializer, this.stateKey,
      {Object? JsonSerializerOptions});

  final TState Function(AgentSession?) _stateInitializer;

  /// The key used to store the provider state in the [AgentSessionStateBag].
  final String stateKey;

  /// Gets the state from the session's [AgentSessionStateBag], or initializes
  /// it using [_stateInitializer] if not present.
  TState getOrInitializeState(AgentSession? session) {
    if (session != null) {
      final (found, state) =
          session.stateBag.tryGetValue<TState>(stateKey);
      if (found && state != null) return state;
    }
    final state = _stateInitializer(session);
    if (session != null) {
      session.stateBag.setValue<TState>(stateKey, state);
    }
    return state;
  }

  /// Saves [state] to the session's [AgentSessionStateBag] using [stateKey].
  /// Does nothing if [session] is `null`.
  void saveState(AgentSession? session, TState state) {
    session?.stateBag.setValue<TState>(stateKey, state);
  }
}
