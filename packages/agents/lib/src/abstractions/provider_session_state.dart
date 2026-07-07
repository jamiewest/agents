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
  ///
  /// [stateRehydrator], when provided, rebuilds a typed [TState] from the raw
  /// JSON-decoded value found in the bag after a session has been restored
  /// from serialized state. Upstream C# deserializes lazily at read time via
  /// reflection-based `System.Text.Json`; Dart has no reflection, so providers
  /// supply this explicit factory instead. Without it, restored raw values
  /// fail the typed read and the state is re-initialized fresh.
  // ignore_for_file: non_constant_identifier_names
  ProviderSessionState(
    this._stateInitializer,
    this.stateKey, {
    TState Function(Object? rawJson)? stateRehydrator,
    Object? jsonSerializerOptions,
  }) : _stateRehydrator = stateRehydrator;

  final TState Function(AgentSession?) _stateInitializer;
  final TState Function(Object? rawJson)? _stateRehydrator;

  /// The key used to store the provider state in the [AgentSessionStateBag].
  final String stateKey;

  /// Gets the state from the session's [AgentSessionStateBag], or initializes
  /// it using [_stateInitializer] if not present.
  ///
  /// When the bag holds a raw JSON value for [stateKey] (a session restored
  /// from serialized state) and a `stateRehydrator` was provided, the raw
  /// value is rehydrated into a typed [TState] and written back to the bag.
  TState getOrInitializeState(AgentSession? session) {
    if (session != null) {
      final (found, state) = session.stateBag.tryGetValue<TState>(stateKey);
      if (found && state != null) return state;

      final rehydrated = _tryRehydrate(session);
      if (rehydrated != null) return rehydrated;
    }
    final state = _stateInitializer(session);
    if (session != null) {
      session.stateBag.setValue<TState>(stateKey, state);
    }
    return state;
  }

  TState? _tryRehydrate(AgentSession session) {
    final rehydrator = _stateRehydrator;
    if (rehydrator == null) return null;
    final (found, raw) = session.stateBag.tryGetValue<Object>(stateKey);
    if (!found || raw == null) return null;
    try {
      final state = rehydrator(raw);
      session.stateBag.setValue<TState>(stateKey, state);
      return state;
    } on Object {
      return null;
    }
  }

  /// Saves [state] to the session's [AgentSessionStateBag] using [stateKey].
  /// Does nothing if [session] is `null`.
  void saveState(AgentSession? session, TState state) {
    session?.stateBag.setValue<TState>(stateKey, state);
  }
}
