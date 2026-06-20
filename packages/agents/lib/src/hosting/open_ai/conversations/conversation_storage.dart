// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Conversations/IConversationStorage.cs.

import 'package:extensions/system.dart';

import '../models/list_response.dart';
import '../models/sort_order.dart';
import '../responses/models/item_resource.dart';
import 'models/conversation.dart';

/// Storage abstraction for conversations and their items.
abstract interface class ConversationStorage {
  /// Creates a new conversation and returns it.
  Future<Conversation> createConversation(
    Conversation conversation, {
    CancellationToken? cancellationToken,
  });

  /// Retrieves a conversation by ID, or null when not found.
  Future<Conversation?> getConversation(
    String conversationId, {
    CancellationToken? cancellationToken,
  });

  /// Updates an existing conversation, returning it, or null when not found.
  Future<Conversation?> updateConversation(
    Conversation conversation, {
    CancellationToken? cancellationToken,
  });

  /// Deletes a conversation and all its items; true when something was removed.
  Future<bool> deleteConversation(
    String conversationId, {
    CancellationToken? cancellationToken,
  });

  /// Appends [items] to a conversation atomically.
  Future<void> addItems(
    String conversationId,
    Iterable<ItemResource> items, {
    CancellationToken? cancellationToken,
  });

  /// Retrieves a single item by ID, or null when not found.
  Future<ItemResource?> getItem(
    String conversationId,
    String itemId, {
    CancellationToken? cancellationToken,
  });

  /// Lists items in a conversation with cursor pagination.
  Future<ListResponse<ItemResource>> listItems(
    String conversationId, {
    int? limit,
    SortOrder? order,
    String? after,
    CancellationToken? cancellationToken,
  });

  /// Deletes a specific item; true when it existed.
  Future<bool> deleteItem(
    String conversationId,
    String itemId, {
    CancellationToken? cancellationToken,
  });
}
