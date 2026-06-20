// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Conversations/ConversationsHttpHandler.cs.
//
// Returns framework-agnostic [ApiResult]s; the shelf router maps them to HTTP
// responses. Request binding (`[FromBody]`/`[FromQuery]`) moves to the router.

import 'package:clock/clock.dart';
import 'package:extensions/system.dart';

import '../api_result.dart';
import '../id_generator.dart';
import '../models/delete_response.dart';
import '../models/error_response.dart';
import '../models/list_response.dart';
import '../models/sort_order.dart';
import '../responses/models/item_resource.dart';
import 'agent_conversation_index.dart';
import 'conversation_storage.dart';
import 'models/conversation.dart';
import 'models/create_conversation_request.dart';
import 'models/create_items_request.dart';
import 'models/update_conversation_request.dart';

/// Handles OpenAI Conversations API operations against a [ConversationStorage].
class ConversationsHandler {
  /// Creates a [ConversationsHandler].
  ConversationsHandler(this._storage, [this._conversationIndex]);

  final ConversationStorage _storage;
  final AgentConversationIndex? _conversationIndex;

  /// Lists conversations for an agent (non-standard extension).
  Future<ApiResult> listConversationsByAgent(
    String? agentId, {
    CancellationToken? cancellationToken,
  }) async {
    if (agentId == null || agentId.isEmpty) {
      return ApiResult.badRequest(
        _error('agent_id query parameter is required.'),
      );
    }

    final index = _conversationIndex;
    if (index == null) {
      return ApiResult.ok(
        ListResponse<Conversation>(
          data: const [],
          hasMore: false,
        ).toJson((c) => c.toJson()),
      );
    }

    final ids = await index.getConversationIds(
      agentId,
      cancellationToken: cancellationToken,
    );
    final conversations = <Conversation>[];
    for (final id in ids.data) {
      final conversation = await _storage.getConversation(
        id,
        cancellationToken: cancellationToken,
      );
      if (conversation != null) {
        conversations.add(conversation);
      }
    }

    return ApiResult.ok(
      ListResponse<Conversation>(
        data: conversations,
        hasMore: false,
      ).toJson((c) => c.toJson()),
    );
  }

  /// Creates a new conversation.
  Future<ApiResult> createConversation(
    CreateConversationRequest request, {
    CancellationToken? cancellationToken,
  }) async {
    final metadata = request.metadata ?? <String, String>{};
    final idGenerator = IdGenerator();
    final conversation = Conversation(
      id: idGenerator.conversationId,
      createdAt: _nowUnixSeconds(),
      metadata: metadata,
    );

    final created = await _storage.createConversation(
      conversation,
      cancellationToken: cancellationToken,
    );

    final items = request.items;
    if (items != null && items.isNotEmpty) {
      final resources = items
          .map((p) => p.toItemResource(idGenerator))
          .toList();
      await _storage.addItems(
        created.id,
        resources,
        cancellationToken: cancellationToken,
      );
    }

    final agentId = created.metadata['agent_id'];
    if (_conversationIndex != null && agentId != null && agentId.isNotEmpty) {
      await _conversationIndex.addConversation(
        agentId,
        created.id,
        cancellationToken: cancellationToken,
      );
    }

    return ApiResult.ok(created.toJson());
  }

  /// Retrieves a conversation by ID.
  Future<ApiResult> getConversation(
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async {
    final conversation = await _storage.getConversation(
      conversationId,
      cancellationToken: cancellationToken,
    );
    return conversation != null
        ? ApiResult.ok(conversation.toJson())
        : ApiResult.notFound(
            _error("Conversation '$conversationId' not found."),
          );
  }

  /// Updates a conversation's metadata.
  Future<ApiResult> updateConversation(
    String conversationId,
    UpdateConversationRequest request, {
    CancellationToken? cancellationToken,
  }) async {
    final existing = await _storage.getConversation(
      conversationId,
      cancellationToken: cancellationToken,
    );
    if (existing == null) {
      return ApiResult.notFound(
        _error("Conversation '$conversationId' not found."),
      );
    }

    final updated = existing.copyWith(metadata: request.metadata);
    final result = await _storage.updateConversation(
      updated,
      cancellationToken: cancellationToken,
    );
    return ApiResult.ok(result!.toJson());
  }

  /// Deletes a conversation and all its items.
  Future<ApiResult> deleteConversation(
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async {
    final conversation = await _storage.getConversation(
      conversationId,
      cancellationToken: cancellationToken,
    );

    final deleted = await _storage.deleteConversation(
      conversationId,
      cancellationToken: cancellationToken,
    );
    if (!deleted) {
      return ApiResult.notFound(
        _error("Conversation '$conversationId' not found."),
      );
    }

    final agentId = conversation?.metadata['agent_id'];
    if (_conversationIndex != null && agentId != null && agentId.isNotEmpty) {
      await _conversationIndex.removeConversation(
        agentId,
        conversationId,
        cancellationToken: cancellationToken,
      );
    }

    return ApiResult.ok(
      DeleteResponse(
        id: conversationId,
        object: 'conversation.deleted',
        deleted: true,
      ).toJson(),
    );
  }

  /// Adds items to a conversation.
  Future<ApiResult> createItems(
    String conversationId,
    CreateItemsRequest request, {
    CancellationToken? cancellationToken,
  }) async {
    final conversation = await _storage.getConversation(
      conversationId,
      cancellationToken: cancellationToken,
    );
    if (conversation == null) {
      return ApiResult.notFound(
        _error("Conversation '$conversationId' not found."),
      );
    }

    final idGenerator = IdGenerator(conversationId: conversationId);
    final created = request.items
        .map((p) => p.toItemResource(idGenerator))
        .toList();
    await _storage.addItems(
      conversationId,
      created,
      cancellationToken: cancellationToken,
    );

    return ApiResult.ok(
      ListResponse<ItemResource>(
        data: created,
        firstId: created.isNotEmpty ? created.first.id : null,
        lastId: created.isNotEmpty ? created.last.id : null,
        hasMore: false,
      ).toJson((i) => i.toJson()),
    );
  }

  /// Lists items in a conversation.
  Future<ApiResult> listItems(
    String conversationId, {
    int? limit,
    String? order,
    String? after,
    CancellationToken? cancellationToken,
  }) async {
    if (limit != null && limit < 1) {
      return ApiResult.badRequest(
        _error(
          "Invalid value for 'limit': must be a positive integer.",
          code: 'invalid_value',
        ),
      );
    }

    final conversation = await _storage.getConversation(
      conversationId,
      cancellationToken: cancellationToken,
    );
    if (conversation == null) {
      return ApiResult.notFound(
        _error("Conversation '$conversationId' not found."),
      );
    }

    final result = await _storage.listItems(
      conversationId,
      limit: limit,
      order: _parseOrder(order),
      after: after,
      cancellationToken: cancellationToken,
    );
    return ApiResult.ok(result.toJson((i) => i.toJson()));
  }

  /// Retrieves a specific item.
  Future<ApiResult> getItem(
    String conversationId,
    String itemId, {
    CancellationToken? cancellationToken,
  }) async {
    final item = await _storage.getItem(
      conversationId,
      itemId,
      cancellationToken: cancellationToken,
    );
    return item != null
        ? ApiResult.ok(item.toJson())
        : ApiResult.notFound(
            _error(
              "Item '$itemId' not found in conversation "
              "'$conversationId'.",
            ),
          );
  }

  /// Deletes a specific item.
  Future<ApiResult> deleteItem(
    String conversationId,
    String itemId, {
    CancellationToken? cancellationToken,
  }) async {
    final deleted = await _storage.deleteItem(
      conversationId,
      itemId,
      cancellationToken: cancellationToken,
    );
    if (!deleted) {
      return ApiResult.notFound(
        _error("Item '$itemId' not found in conversation '$conversationId'."),
      );
    }

    return ApiResult.ok(
      DeleteResponse(
        id: itemId,
        object: 'conversation.item.deleted',
        deleted: true,
      ).toJson(),
    );
  }

  static SortOrder? _parseOrder(String? order) {
    if (order == null) {
      return null;
    }
    return order.toLowerCase() == 'asc'
        ? SortOrder.ascending
        : SortOrder.descending;
  }

  static Map<String, dynamic> _error(String message, {String? code}) =>
      ErrorResponse(
        error: ErrorDetails(
          message: message,
          type: 'invalid_request_error',
          code: code,
        ),
      ).toJson();

  static int _nowUnixSeconds() =>
      clock.now().toUtc().millisecondsSinceEpoch ~/ 1000;
}
