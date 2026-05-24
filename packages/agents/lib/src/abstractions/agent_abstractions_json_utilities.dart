/// Provides utility configurations for JSON serialization within the agent
/// abstractions layer.
class AgentAbstractionsJsonUtilities {
  AgentAbstractionsJsonUtilities._();

  /// A sentinel Object passed as `JsonSerializerOptions` when the caller
  /// wants default serialization (i.e., plain `dart:convert` `jsonEncode` /
  /// `jsonDecode` with no custom converters).
  static const Object defaultOptions = _DefaultOptions();
}

class _DefaultOptions {
  const _DefaultOptions();
}
