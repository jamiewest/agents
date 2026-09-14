// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Conversations/IsolationKeyScopedConversationStorage.cs.

import 'package:extensions/system.dart';

import '../isolation_key_resolver.dart';
import '../models/list_response.dart';
import '../models/sort_order.dart';
import '../responses/models/item_resource.dart';
import 'conversation_storage.dart';
import 'models/conversation.dart';

/// A delegating [ConversationStorage] that scopes conversation keys by the
/// caller's isolation key, so that a conversation can only be resolved by the
/// caller that created it.
///
/// Only the storage key is scoped. The [Conversation.id] observed by callers
/// is always the bare identifier, so the wire format of the OpenAI
/// Conversations API is unchanged.
class IsolationKeyScopedConversationStorage implements ConversationStorage {
  /// Wraps [innerStorage], scoping identifiers through [resolver].
  IsolationKeyScopedConversationStorage(this._innerStorage, this._resolver);

  final ConversationStorage _innerStorage;
  final IsolationKeyResolver _resolver;

  @override
  Future<Conversation> createConversation(
    Conversation conversation, {
    CancellationToken? cancellationToken,
  }) async {
    final key = await _resolver.getKey(cancellationToken: cancellationToken);
    final created = await _innerStorage.createConversation(
      _scopeConversation(conversation, key),
      cancellationToken: cancellationToken,
    );
    return _unscopeConversation(created, key);
  }

  @override
  Future<Conversation?> getConversation(
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async {
    final key = await _resolver.getKey(cancellationToken: cancellationToken);
    final conversation = await _innerStorage.getConversation(
      IsolationKeyResolver.scopeId(conversationId, key),
      cancellationToken: cancellationToken,
    );
    return conversation == null
        ? null
        : _unscopeConversation(conversation, key);
  }

  @override
  Future<Conversation?> updateConversation(
    Conversation conversation, {
    CancellationToken? cancellationToken,
  }) async {
    final key = await _resolver.getKey(cancellationToken: cancellationToken);
    final updated = await _innerStorage.updateConversation(
      _scopeConversation(conversation, key),
      cancellationToken: cancellationToken,
    );
    return updated == null ? null : _unscopeConversation(updated, key);
  }

  @override
  Future<bool> deleteConversation(
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async => _innerStorage.deleteConversation(
    await _resolver.scopeIdAsync(
      conversationId,
      cancellationToken: cancellationToken,
    ),
    cancellationToken: cancellationToken,
  );

  @override
  Future<void> addItems(
    String conversationId,
    Iterable<ItemResource> items, {
    CancellationToken? cancellationToken,
  }) async => _innerStorage.addItems(
    await _resolver.scopeIdAsync(
      conversationId,
      cancellationToken: cancellationToken,
    ),
    items,
    cancellationToken: cancellationToken,
  );

  @override
  Future<ItemResource?> getItem(
    String conversationId,
    String itemId, {
    CancellationToken? cancellationToken,
  }) async => _innerStorage.getItem(
    await _resolver.scopeIdAsync(
      conversationId,
      cancellationToken: cancellationToken,
    ),
    itemId,
    cancellationToken: cancellationToken,
  );

  @override
  Future<ListResponse<ItemResource>> listItems(
    String conversationId, {
    int? limit,
    SortOrder? order,
    String? after,
    CancellationToken? cancellationToken,
  }) async => _innerStorage.listItems(
    await _resolver.scopeIdAsync(
      conversationId,
      cancellationToken: cancellationToken,
    ),
    limit: limit,
    order: order,
    after: after,
    cancellationToken: cancellationToken,
  );

  @override
  Future<bool> deleteItem(
    String conversationId,
    String itemId, {
    CancellationToken? cancellationToken,
  }) async => _innerStorage.deleteItem(
    await _resolver.scopeIdAsync(
      conversationId,
      cancellationToken: cancellationToken,
    ),
    itemId,
    cancellationToken: cancellationToken,
  );

  static Conversation _scopeConversation(
    Conversation conversation,
    String? key,
  ) => key == null
      ? conversation
      : conversation.copyWith(
          id: IsolationKeyResolver.scopeId(conversation.id, key),
        );

  static Conversation _unscopeConversation(
    Conversation conversation,
    String? key,
  ) => key == null
      ? conversation
      : conversation.copyWith(
          id: IsolationKeyResolver.unscopeId(conversation.id, key),
        );
}
