// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Conversations/Models/UpdateConversationRequest.cs.

/// Request to update an existing conversation.
class UpdateConversationRequest {
  /// Creates an [UpdateConversationRequest].
  const UpdateConversationRequest({required this.metadata});

  /// Parses an [UpdateConversationRequest] from a decoded JSON object.
  factory UpdateConversationRequest.fromJson(Map<String, dynamic> json) =>
      UpdateConversationRequest(
        metadata: (json['metadata'] as Map).cast<String, String>(),
      );

  /// Up to 16 key-value pairs to attach to the conversation.
  final Map<String, String> metadata;
}
