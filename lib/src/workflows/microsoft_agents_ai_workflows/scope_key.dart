import 'scope_id.dart';

/// Represents a unique key within a specific scope, combining a scope
/// identifier and a key String.
class ScopeKey {
  /// Initializes a new instance of the [ScopeKey] class.
  ///
  /// [executorId] The unique identifier for the executor.
  ///
  /// [scopeName] The name of the scope, if any.
  ///
  /// [key] The unique key within the specified scope.
  ScopeKey(
    String key, {
    String? executorId = null,
    String? scopeName = null,
    ScopeId? scopeId = null,
  }) : key = key;

  /// The identifier for the scope associated with this key.
  final ScopeId scopeId;

  /// The unique key within the specified scope.
  final String key;

  @override
  String toString() {
    return '${this.scopeId}/${this.key}';
  }

  @override
  bool equals(Object? obj) {
    if (obj is ScopeKey) {
      final other = obj as ScopeKey;
      return this.scopeId == other.scopeId && this.key == other.key;
    }
    return false;
  }

  @override
  int hashCode {
    return HashCode.combine(this.scopeId, this.key);
  }
}
