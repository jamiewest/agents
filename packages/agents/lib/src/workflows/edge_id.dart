/// Identifies a workflow edge.
class EdgeId {
  /// Creates an edge identifier.
  const EdgeId(this.value);

  /// Gets the string value of the identifier.
  final String value;

  @override
  bool operator ==(Object other) => other is EdgeId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
