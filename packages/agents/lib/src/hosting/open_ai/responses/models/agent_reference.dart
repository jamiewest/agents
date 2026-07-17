// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/Models/AgentId.cs (the AgentReference wire model;
// the internal AgentId/AgentIdType entity models are not yet consumed by
// this port).

/// Represents an agent reference supplied on a `create response` request.
class AgentReference {
  /// Creates an [AgentReference].
  const AgentReference({
    this.type = 'agent_reference',
    required this.name,
    this.version,
  });

  /// Parses an [AgentReference] from a decoded JSON object.
  factory AgentReference.fromJson(Map<String, dynamic> json) => AgentReference(
    type: json['type'] as String? ?? 'agent_reference',
    name: json['name'] as String? ?? '',
    version: json['version'] as String?,
  );

  /// The type of the reference (e.g., `agent` or `agent_reference`).
  final String type;

  /// The name of the agent.
  final String name;

  /// The version of the agent.
  final String? version;

  /// Converts this reference to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'type': type,
    'name': name,
    if (version != null) 'version': version,
  };
}
