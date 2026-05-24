/// A tool call that an agent is expected to make.
class ExpectedToolCall {
  ExpectedToolCall(this.name, {this.arguments});

  /// The tool/function name.
  String name;

  /// Expected arguments. `null` means "don't check arguments".
  Map<String, Object?>? arguments;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExpectedToolCall &&
        name == other.name &&
        _mapEquals(arguments, other.arguments);
  }

  @override
  int get hashCode =>
      Object.hash(name, Object.hashAll(arguments?.entries ?? []));
}

bool _mapEquals(Map<String, Object?>? left, Map<String, Object?>? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
