// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/Models/ConversationReference.cs.

/// A reference to a conversation by ID.
class ConversationReference {
  /// Creates a [ConversationReference].
  const ConversationReference({required this.id});

  /// Parses a [ConversationReference] from JSON (object with `id`, or a string).
  factory ConversationReference.fromJson(Object? json) {
    if (json is String) {
      return ConversationReference(id: json);
    }
    if (json is Map<String, dynamic>) {
      return ConversationReference(id: json['id'] as String);
    }
    throw FormatException('Unexpected ConversationReference JSON: $json');
  }

  /// The conversation ID.
  final String id;

  /// Serializes this reference.
  Map<String, dynamic> toJson() => {'id': id};
}
