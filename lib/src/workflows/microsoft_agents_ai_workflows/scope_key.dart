import 'scope_id.dart';

/// A unique key within a specific scope, combining a [ScopeId] and a key string.
///
/// Unlike [ScopeId] equality (which ignores executor id when a scope name is
/// set), two [ScopeKey]s are equal only when both their [ScopeId] **and** [key]
/// are equal.
class ScopeKey {
  /// Creates a [ScopeKey] from an existing [scopeId] and a [key].
  ScopeKey(this.scopeId, this.key)
      : assert(key.isNotEmpty, 'key must not be empty');

  /// Creates a [ScopeKey] from raw [executorId], optional [scopeName], and [key].
  ScopeKey.fromParts(String executorId, String? scopeName, String key)
      : this(ScopeId(executorId, scopeName), key);

  /// The scope identifier.
  final ScopeId scopeId;

  /// The unique key within the scope.
  final String key;

  @override
  String toString() => '$scopeId/$key';

  @override
  bool operator ==(Object other) {
    if (other is ScopeKey) {
      return scopeId == other.scopeId && key == other.key;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(scopeId, key);
}
