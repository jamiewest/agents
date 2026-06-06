/// Configuration options for an [A2AAgent], including its identifier,
/// name, and description.
class A2AAgentOptions {
  /// Creates an [A2AAgentOptions] instance.
  A2AAgentOptions({this.id, this.name, this.description});

  /// The agent id.
  String? id;

  /// The agent name.
  String? name;

  /// The agent description.
  String? description;

  /// Returns a shallow copy of this instance.
  A2AAgentOptions clone() =>
      A2AAgentOptions(id: id, name: name, description: description);
}
