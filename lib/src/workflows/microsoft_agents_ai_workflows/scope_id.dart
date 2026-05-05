/// A unique identifier for a scope within an executor.
///
/// If [scopeName] is `null`, this references the executor's private default
/// scope. If [scopeName] is provided, it references a named shared scope that
/// is independent of the executor.
class ScopeId {
  /// Creates a [ScopeId] for [executorId], optionally scoped by [scopeName].
  ScopeId(this.executorId, {this.scopeName});

  /// The unique identifier of the executor.
  final String executorId;

  /// The scope name, or `null` for the executor's private default scope.
  final String? scopeName;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ScopeId) return false;
    if (scopeName == null && other.scopeName == null) {
      return executorId == other.executorId;
    }
    if (scopeName != null && other.scopeName != null) {
      return scopeName == other.scopeName;
    }
    return false;
  }

  @override
  int get hashCode =>
      scopeName == null ? executorId.hashCode : scopeName.hashCode;

  @override
  String toString() => '$executorId/${scopeName ?? "default"}';
}
