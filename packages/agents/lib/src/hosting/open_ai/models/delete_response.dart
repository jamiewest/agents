// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Microsoft.Agents.AI.Hosting.OpenAI/Models/DeleteResponse.cs.

/// Response for a delete operation.
class DeleteResponse {
  /// Creates a [DeleteResponse].
  const DeleteResponse({
    required this.id,
    required this.object,
    required this.deleted,
  });

  /// The ID of the deleted object.
  final String id;

  /// The object type.
  final String object;

  /// Whether the object was successfully deleted.
  final bool deleted;

  /// Serializes this delete response.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'object': object,
    'deleted': deleted,
  };
}
