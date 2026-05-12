/// Identifies an executor instance by an optional case-insensitive string id.
///
/// [ExecutorIdentity.none] represents the absence of an identity.
class ExecutorIdentity {
  /// Creates an [ExecutorIdentity] with the optional [id].
  const ExecutorIdentity([this.id]);

  /// The identity that carries no id.
  static const ExecutorIdentity none = ExecutorIdentity();

  /// The optional string identifier.
  final String? id;

  @override
  bool operator ==(Object other) {
    if (other is ExecutorIdentity) {
      if (id == null) return other.id == null;
      if (other.id == null) return false;
      return id!.toLowerCase() == other.id!.toLowerCase();
    }
    if (other is String) {
      return id != null && id!.toLowerCase() == other.toLowerCase();
    }
    return false;
  }

  @override
  int get hashCode => id == null ? 0 : id!.toLowerCase().hashCode;

  @override
  String toString() => id ?? '';
}
