import '../scope_id.dart';

/// Identifies an update within a specific scope.
///
/// Unlike [ScopeId] equality, two [UpdateKey]s that differ only by their
/// [ScopeId.executorId] are considered different — updates from different
/// executors must be tracked separately until merged at step transition.
class UpdateKey {
  /// Creates an [UpdateKey] from an existing [ScopeId] and [key].
  UpdateKey(this.scopeId, this.key)
      : assert(key.isNotEmpty, 'key must not be empty');

  /// Creates an [UpdateKey] from raw [executorId], optional [scopeName], and
  /// [key].
  UpdateKey.fromParts(String executorId, String? scopeName, String key)
      : this(ScopeId(executorId, scopeName), key);

  /// The scope identifier.
  final ScopeId scopeId;

  /// The key within the scope.
  final String key;

  @override
  String toString() => '$scopeId/$key';

  /// Returns `true` when this key's scope matches [other].
  ///
  /// When [strict] is `true`, also requires [ScopeId.executorId] to match.
  bool isMatchingScope(ScopeId other, {bool strict = false}) =>
      scopeId == other &&
      (!strict || scopeId.executorId == other.executorId);

  @override
  bool operator ==(Object other) {
    if (other is UpdateKey) {
      return isMatchingScope(other.scopeId, strict: true) && key == other.key;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(scopeId.executorId, scopeId.scopeName, key);
}
