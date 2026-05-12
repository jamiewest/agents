import '../portable_value.dart';
import '../scope_id.dart';
import 'state_update.dart';

/// Stores key/value state for a single scope, keyed by [ScopeId].
final class StateScope {
  /// Creates a [StateScope] for [scopeId].
  StateScope(this.scopeId);

  /// Gets the scope identifier.
  final ScopeId scopeId;

  final Map<String, PortableValue> _stateData = {};

  /// Returns the set of all stored keys.
  Set<String> readKeys() => Set<String>.of(_stateData.keys);

  /// Returns `true` when a value typed [T] is stored under [key].
  bool contains<T>(String key) {
    final value = _stateData[key];
    return value != null && value.isValue<T>();
  }

  /// Returns `true` when [key] has any stored value.
  bool containsKey(String key) => _stateData.containsKey(key);

  /// Reads the stored value for [key] as [T], or `null` if absent.
  T? readState<T>(String key) {
    final value = _stateData[key];
    if (value == null) return null;
    if (T == PortableValue) return value as T?;
    return value.asValue<T>();
  }

  /// Applies a batch of [updates] to this scope.
  void writeState(Map<String, List<StateUpdate>> updates) {
    for (final entry in updates.entries) {
      final stateUpdates = entry.value;
      if (stateUpdates.isEmpty) continue;
      if (stateUpdates.length > 1) {
        throw StateError(
          'Expected exactly one update for key "${entry.key}".',
        );
      }
      final update = stateUpdates.first;
      if (update.isDelete) {
        _stateData.remove(entry.key);
      } else {
        _stateData[entry.key] = PortableValue(update.value!);
      }
    }
  }

  /// Returns all stored entries for export.
  Iterable<MapEntry<String, PortableValue>> exportStates() =>
      _stateData.entries;

  /// Directly imports [state] under [key], bypassing the update queue.
  void importState(String key, PortableValue state) {
    _stateData[key] = state;
  }
}
