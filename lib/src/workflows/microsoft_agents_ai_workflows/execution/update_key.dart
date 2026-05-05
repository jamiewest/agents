import '../scope_id.dart';
import '../scope_key.dart';

/// Represents a unique key used to identify an update within a specific
/// scope.
///
/// Remarks: An [UpdateKey] is composed of a [ScopeId] and a key, similar to
/// [ScopeKey]. The difference is in how equality is determined: Unlike
/// ScopeKey, two UpdateKeys that differ only by their ScopeId's ExecutorId
/// are considered different, because updates coming from different executors
/// need to be tracked separately, until they are marged (if appropriate) and
/// published during a step transition.
///
/// [scopeId]
///
/// [key]
class UpdateKey {
  /// Represents a unique key used to identify an update within a specific
  /// scope.
  ///
  /// Remarks: An [UpdateKey] is composed of a [ScopeId] and a key, similar to
  /// [ScopeKey]. The difference is in how equality is determined: Unlike
  /// ScopeKey, two UpdateKeys that differ only by their ScopeId's ExecutorId
  /// are considered different, because updates coming from different executors
  /// need to be tracked separately, until they are marged (if appropriate) and
  /// published during a step transition.
  ///
  /// [scopeId]
  ///
  /// [key]
  UpdateKey(
    String key, {
    ScopeId? scopeId = null,
    String? executorId = null,
    String? scopeName = null,
  }) : key = key;

  final ScopeId scopeId = scopeId;

  final String key = key;

  @override
  String toString() {
    return '${this.scopeId}/${this.key}';
  }

  bool isMatchingScope(ScopeId scopeId, {bool? strict}) {
    return this.scopeId == scopeId &&
        (!strict || this.scopeId.executorId == scopeId.executorId);
  }

  @override
  bool equals(Object? obj) {
    if (obj is UpdateKey) {
      final other = obj as UpdateKey;
      return this.isMatchingScope(other.scopeId, strict: true) &&
          this.key == other.key;
    }
    return false;
  }

  @override
  int getHashCode() {
    return HashCode.combine(
      this.scopeId.executorId,
      this.scopeId.scopeName,
      this.key,
    );
  }
}
