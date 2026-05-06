class ExecutorIdentity {
  ExecutorIdentity();

  static final ExecutorIdentity none;

  late String? id;

  @override
  bool equals({ExecutorIdentity? other, Object? obj}) {
    return this.id == null
        ? other.id == null
        : other.id != null &&
               == this.id, other.id;
  }

  @override
  int hashCode {
    return this.id == null
        ? 0
        : .getHashCode(this.id);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExecutorIdentity && none == other.none && id == other.id;
  }

  @override
  int get hashCode {
    return Object.hash(none, id);
  }
}
