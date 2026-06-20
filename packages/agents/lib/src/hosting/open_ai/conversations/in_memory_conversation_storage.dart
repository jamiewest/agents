// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Conversations/InMemoryConversationStorage.cs.
//
// The upstream uses `MemoryCache` with per-entry sliding expiration and locks.
// Dart runs one isolate per request loop, so this port uses a plain in-memory
// map without locks. Cache eviction/expiration is not enforced; this store is
// intended for development and testing only (as is the upstream).

import 'package:extensions/system.dart';

import '../models/list_response.dart';
import '../models/sort_order.dart';
import '../responses/models/item_resource.dart';
import 'conversation_storage.dart';
import 'models/conversation.dart';

/// In-memory [ConversationStorage] for development and testing.
class InMemoryConversationStorage implements ConversationStorage {
  final Map<String, _ConversationState> _conversations = {};

  @override
  Future<Conversation> createConversation(
    Conversation conversation, {
    CancellationToken? cancellationToken,
  }) async {
    _conversations[conversation.id] = _ConversationState(conversation);
    return conversation;
  }

  @override
  Future<Conversation?> getConversation(
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async => _conversations[conversationId]?.conversation;

  @override
  Future<Conversation?> updateConversation(
    Conversation conversation, {
    CancellationToken? cancellationToken,
  }) async {
    final state = _conversations[conversation.id];
    if (state == null) {
      return null;
    }
    state.conversation = conversation;
    return conversation;
  }

  @override
  Future<bool> deleteConversation(
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async => _conversations.remove(conversationId) != null;

  @override
  Future<void> addItems(
    String conversationId,
    Iterable<ItemResource> items, {
    CancellationToken? cancellationToken,
  }) async {
    _conversations[conversationId]?.items.addAll(items);
  }

  @override
  Future<ItemResource?> getItem(
    String conversationId,
    String itemId, {
    CancellationToken? cancellationToken,
  }) async {
    final state = _conversations[conversationId];
    if (state == null) {
      return null;
    }
    for (final item in state.items) {
      if (item.id == itemId) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<ListResponse<ItemResource>> listItems(
    String conversationId, {
    int? limit,
    SortOrder? order,
    String? after,
    CancellationToken? cancellationToken,
  }) async {
    final state = _conversations[conversationId];
    final all = state?.items ?? const <ItemResource>[];
    final effectiveLimit = (limit ?? 20).clamp(1, 100);
    final ordered = (order ?? SortOrder.descending) == SortOrder.ascending
        ? all.toList()
        : all.reversed.toList();

    var startIndex = 0;
    if (after != null) {
      final idx = ordered.indexWhere((i) => i.id == after);
      if (idx >= 0) {
        startIndex = idx + 1;
      }
    }

    final page = ordered
        .skip(startIndex)
        .take(effectiveLimit)
        .toList(growable: false);
    final hasMore = ordered.length > startIndex + effectiveLimit;

    return ListResponse<ItemResource>(
      data: page,
      firstId: page.isNotEmpty ? page.first.id : null,
      lastId: page.isNotEmpty ? page.last.id : null,
      hasMore: hasMore,
    );
  }

  @override
  Future<bool> deleteItem(
    String conversationId,
    String itemId, {
    CancellationToken? cancellationToken,
  }) async {
    final state = _conversations[conversationId];
    if (state == null) {
      return false;
    }
    final before = state.items.length;
    state.items.removeWhere((i) => i.id == itemId);
    return state.items.length != before;
  }
}

class _ConversationState {
  _ConversationState(this.conversation);

  Conversation conversation;
  final List<ItemResource> items = [];
}
