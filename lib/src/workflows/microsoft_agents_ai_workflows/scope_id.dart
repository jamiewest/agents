/// A unique identifier for a scope within an executor.
///
/// If [scopeName] is `null`, the `ScopeId` references the executor's private
/// default scope. Otherwise it references a shared scope with the given name,
/// regardless of [executorId].
class ScopeId {
  /// Creates a [ScopeId].
  ScopeId(this.executorId, [this.scopeName])
      : assert(executorId.isNotEmpty, 'executorId must not be empty');

  /// The unique identifier of the executor.
  final String executorId;

  /// The name of the scope, or `null` for the executor's private scope.
  final String? scopeName;

  @override
  String toString() => '$executorId/${scopeName ?? 'default'}';

  @override
  bool operator ==(Object other) {
    if (other is ScopeId) {
      if (scopeName == null && other.scopeName == null) {
        return executorId == other.executorId;
      }
      if (scopeName != null && other.scopeName != null) {
        return scopeName == other.scopeName;
      }
    }
    return false;
  }

  @override
  int get hashCode =>
      scopeName == null ? executorId.hashCode : scopeName.hashCode;
}
