// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Conversations/Models/CreateConversationRequest.cs.

import '../../responses/models/item_param.dart';

/// Request to create a new conversation.
class CreateConversationRequest {
  /// Creates a [CreateConversationRequest].
  const CreateConversationRequest({this.items, this.metadata});

  /// Parses a [CreateConversationRequest] from a decoded JSON object.
  factory CreateConversationRequest.fromJson(Map<String, dynamic> json) =>
      CreateConversationRequest(
        items: (json['items'] as List?)
            ?.map((i) => ItemParam.fromJson(i as Map<String, dynamic>))
            .toList(),
        metadata: (json['metadata'] as Map?)?.cast<String, String>(),
      );

  /// Up to 20 initial items to include in the conversation context.
  final List<ItemParam>? items;

  /// Up to 16 key-value pairs to attach to the conversation.
  final Map<String, String>? metadata;
}
