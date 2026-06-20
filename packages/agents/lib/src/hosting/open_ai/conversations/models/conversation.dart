// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Conversations/Models/Conversation.cs.

/// Represents a conversation in the system.
class Conversation {
  /// Creates a [Conversation].
  Conversation({
    required this.id,
    required this.createdAt,
    Map<String, String>? metadata,
  }) : metadata = metadata ?? <String, String>{};

  /// Parses a [Conversation] from a decoded JSON object.
  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    createdAt: json['created_at'] as int,
    metadata: (json['metadata'] as Map?)?.cast<String, String>(),
  );

  /// The unique identifier for the conversation.
  final String id;

  /// The Unix timestamp (seconds) for when the conversation was created.
  final int createdAt;

  /// Up to 16 key-value pairs attached to the conversation.
  final Map<String, String> metadata;

  /// The object type, always `conversation`.
  String get object => 'conversation';

  /// Returns a copy of this conversation with replaced [metadata].
  Conversation copyWith({Map<String, String>? metadata}) => Conversation(
    id: id,
    createdAt: createdAt,
    metadata: metadata ?? this.metadata,
  );

  /// Serializes this conversation.
  Map<String, dynamic> toJson() => {
    'id': id,
    'object': object,
    'created_at': createdAt,
    'metadata': metadata,
  };
}
