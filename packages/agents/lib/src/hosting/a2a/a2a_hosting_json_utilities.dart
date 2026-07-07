/// Provides utility configurations for JSON serialization within the A2A
/// hosting layer.
///
/// Upstream C# chains `System.Text.Json` type-info resolvers (agent
/// abstractions first, then the A2A SDK protocol types) to support AOT and
/// trimming. Dart's `dart:convert` has no resolver mechanism, so this class
/// mirrors the sentinel idiom of `AgentAbstractionsJsonUtilities`: pass
/// [defaultOptions] where an API accepts `jsonSerializerOptions` to request
/// default serialization behavior.
class A2AHostingJsonUtilities {
  A2AHostingJsonUtilities._();

  /// A sentinel Object passed as `jsonSerializerOptions` when the caller
  /// wants default A2A hosting serialization.
  static const Object defaultOptions = _DefaultOptions();
}

class _DefaultOptions {
  const _DefaultOptions();
}
