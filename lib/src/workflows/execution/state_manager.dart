import '../portable_value.dart';
import '../scope_id.dart';
import '../scope_key.dart';
import 'state_scope.dart';
import 'state_update.dart';
import 'step_tracer.dart';
import 'update_key.dart';

/// Manages workflow execution state using a two-phase write pattern.
///
/// Writes are first queued via [writeState] then flushed to their [StateScope]
/// by [publishUpdates]. Reads apply any queued updates on top of the persisted
/// scope data so callers always see a consistent view.
final class StateManager {
  final Map<ScopeId, StateScope> _scopes = {};
  final Map<UpdateKey, StateUpdate> _queuedUpdates = {};

  // ── scope helpers ────────────────────────────────────────────────────────

  StateScope _getOrCreateScope(ScopeId scopeId) =>
      _scopes.putIfAbsent(scopeId, () => StateScope(scopeId));

  Iterable<UpdateKey> _getUpdatesForScopeStrict(ScopeId scopeId) =>
      _queuedUpdates.keys
          .where((key) => key.isMatchingScope(scopeId, strict: true));

  // ── read ─────────────────────────────────────────────────────────────────

  /// Returns the set of keys stored in [scopeId], merging queued updates.
  Set<String> readKeys(String executorId, [String? scopeName]) =>
      _readKeys(ScopeId(executorId, scopeName));

  Set<String> _readKeys(ScopeId scopeId) {
    final scope = _getOrCreateScope(scopeId);
    final keys = scope.readKeys();
    return _applyUnpublishedUpdates(scopeId, keys);
  }

  Set<String> _applyUnpublishedUpdates(ScopeId scopeId, Set<String> keys) {
    for (final key in _getUpdatesForScopeStrict(scopeId)) {
      final update = _queuedUpdates[key]!;
      if (update.isDelete) {
        keys.remove(update.key);
      } else {
        keys.add(update.key);
      }
    }
    return keys;
  }

  /// Reads the value for [key] as [T] in [executorId]/[scopeName].
  T? readState<T>(String executorId, String? scopeName, String key) =>
      _readState<T>(ScopeId(executorId, scopeName), key);

  T? _readState<T>(ScopeId scopeId, String key) {
    if (T == Object) {
      throw StateError(
        "Reading state as 'Object' is not supported. Use 'PortableValue' "
        'instead for variants.',
      );
    }

    final stateKey = UpdateKey(scopeId, key);

    if (_queuedUpdates.containsKey(stateKey)) {
      final update = _queuedUpdates[stateKey]!;
      if (update.isDelete || update.value == null) return null;
      final v = update.value;
      if (v is T) return v;
      if (T == PortableValue && v != null) return PortableValue(v) as T;
      throw StateError(
        "State for key '$key' in scope '$scopeId' is not of type '$T'.",
      );
    }

    final scope = _getOrCreateScope(scopeId);
    if (!scope.containsKey(key)) return null;
    return scope.readState<T>(key);
  }

  /// Reads the value for [key] as [T], initialising it with [factory] if
  /// absent.
  T readOrInitState<T>(
    String executorId,
    String? scopeName,
    String key,
    T Function() factory,
  ) => _readOrInitState(ScopeId(executorId, scopeName), key, factory);

  T _readOrInitState<T>(ScopeId scopeId, String key, T Function() factory) {
    final existing = _readState<T>(scopeId, key);
    if (existing != null) return existing;
    final initial = factory();
    writeState(scopeId.executorId, scopeId.scopeName, key, initial);
    return initial;
  }

  // ── write ────────────────────────────────────────────────────────────────

  /// Queues an upsert of [value] under [key] in [executorId]/[scopeName].
  void writeState<T>(String executorId, String? scopeName, String key, T value) {
    final stateKey = UpdateKey(ScopeId(executorId, scopeName), key);
    _queuedUpdates[stateKey] = StateUpdate.update(key, value);
  }

  /// Queues deletion of [key] in [executorId]/[scopeName].
  void clearState(String executorId, String? scopeName, String key) {
    final stateKey = UpdateKey(ScopeId(executorId, scopeName), key);
    _queuedUpdates[stateKey] = StateUpdate.delete(key);
  }

  /// Queues deletion of all keys in [executorId]/[scopeName].
  void clearScope(String executorId, [String? scopeName]) {
    final scopeId = ScopeId(executorId, scopeName);
    if (_scopes.containsKey(scopeId)) {
      final scope = _scopes[scopeId]!;
      for (final existingKey in scope.readKeys()) {
        final updateKey = UpdateKey(scopeId, existingKey);
        if (!_queuedUpdates.containsKey(updateKey) ||
            !_queuedUpdates[updateKey]!.isDelete) {
          _queuedUpdates[updateKey] = StateUpdate.delete(existingKey);
        }
      }
    }
    for (final updateKey in _getUpdatesForScopeStrict(scopeId).toList()) {
      final update = _queuedUpdates[updateKey]!;
      if (!update.isDelete) {
        _queuedUpdates[updateKey] = StateUpdate.delete(update.key);
      }
    }
  }

  // ── publish ──────────────────────────────────────────────────────────────

  /// Flushes all queued updates to their respective [StateScope]s.
  void publishUpdates([IStepTracer? tracer]) {
    if (_queuedUpdates.isEmpty) return;

    final updatesByScope = <ScopeId, Map<String, List<StateUpdate>>>{};
    for (final entry in _queuedUpdates.entries) {
      final scopeUpdates = updatesByScope.putIfAbsent(
        entry.key.scopeId,
        () => <String, List<StateUpdate>>{},
      );
      (scopeUpdates[entry.key.key] ??= []).add(entry.value);
    }

    tracer?.traceStatePublished();

    for (final entry in updatesByScope.entries) {
      _getOrCreateScope(entry.key).writeState(entry.value);
    }

    _queuedUpdates.clear();
  }

  // ── checkpoint export/import ─────────────────────────────────────────────

  /// Exports all scope state as a flat [ScopeKey] → [PortableValue] map.
  ///
  /// Throws if there are queued updates that have not been published.
  Map<ScopeKey, PortableValue> exportState() {
    if (_queuedUpdates.isNotEmpty) {
      throw StateError(
        'Cannot export state while there are queued updates. '
        'Call publishUpdates() first.',
      );
    }
    return {
      for (final scope in _scopes.values)
        for (final entry in scope.exportStates())
          ScopeKey(scope.scopeId, entry.key): entry.value,
    };
  }

  /// Imports [stateData] from a checkpoint, replacing all existing state.
  void importState(Map<ScopeKey, PortableValue> stateData) {
    if (_queuedUpdates.isNotEmpty) {
      throw StateError(
        'Cannot import state while there are queued updates. '
        'Call publishUpdates() first.',
      );
    }
    _queuedUpdates.clear();
    _scopes.clear();
    for (final entry in stateData.entries) {
      _getOrCreateScope(entry.key.scopeId)
          .importState(entry.key.key, entry.value);
    }
  }

}
