// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Conversations/Models/AddMessageRequest.cs (CreateItemsRequest).

import '../../responses/models/item_param.dart';

/// Request to create items in a conversation.
class CreateItemsRequest {
  /// Creates a [CreateItemsRequest].
  const CreateItemsRequest({required this.items});

  /// Parses a [CreateItemsRequest] from a decoded JSON object.
  factory CreateItemsRequest.fromJson(Map<String, dynamic> json) =>
      CreateItemsRequest(
        items: (json['items'] as List)
            .map((i) => ItemParam.fromJson(i as Map<String, dynamic>))
            .toList(),
      );

  /// Up to 20 items to add to the conversation.
  final List<ItemParam> items;
}
