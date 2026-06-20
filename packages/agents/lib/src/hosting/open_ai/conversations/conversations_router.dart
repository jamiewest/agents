// Copyright (c) Microsoft. All rights reserved.
//
// Ported from EndpointRouteBuilderExtensions.Conversations.cs.
//
// Builds a `shelf_router` [Router] for the OpenAI Conversations API. Mount it
// under `/v1/conversations` in the host (e.g. `app.mount('/v1/conversations',
// openAIConversationsRouter(...))`).

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../api_result.dart';
import 'agent_conversation_index.dart';
import 'conversation_storage.dart';
import 'conversations_handler.dart';
import 'models/create_conversation_request.dart';
import 'models/create_items_request.dart';
import 'models/update_conversation_request.dart';

/// Builds a [Router] exposing the OpenAI Conversations API.
///
/// Routes are relative, so mount the returned router at `/v1/conversations`.
Router openAIConversationsRouter({
  required ConversationStorage storage,
  AgentConversationIndex? index,
}) {
  final handler = ConversationsHandler(storage, index);
  final router = Router();

  router.get('/', (Request request) async {
    final agentId = request.url.queryParameters['agent_id'];
    return _toResponse(await handler.listConversationsByAgent(agentId));
  });

  router.post('/', (Request request) async {
    final body = await _readJson(request);
    return _toResponse(
      await handler.createConversation(
        CreateConversationRequest.fromJson(body),
      ),
    );
  });

  router.get('/<conversationId>', (
    Request request,
    String conversationId,
  ) async {
    return _toResponse(await handler.getConversation(conversationId));
  });

  router.post('/<conversationId>', (
    Request request,
    String conversationId,
  ) async {
    final body = await _readJson(request);
    return _toResponse(
      await handler.updateConversation(
        conversationId,
        UpdateConversationRequest.fromJson(body),
      ),
    );
  });

  router.delete('/<conversationId>', (
    Request request,
    String conversationId,
  ) async {
    return _toResponse(await handler.deleteConversation(conversationId));
  });

  router.post('/<conversationId>/items', (
    Request request,
    String conversationId,
  ) async {
    final body = await _readJson(request);
    return _toResponse(
      await handler.createItems(
        conversationId,
        CreateItemsRequest.fromJson(body),
      ),
    );
  });

  router.get('/<conversationId>/items', (
    Request request,
    String conversationId,
  ) async {
    final query = request.url.queryParameters;
    final limitRaw = query['limit'];
    return _toResponse(
      await handler.listItems(
        conversationId,
        limit: limitRaw == null ? null : int.tryParse(limitRaw),
        order: query['order'],
        after: query['after'],
      ),
    );
  });

  router.get('/<conversationId>/items/<itemId>', (
    Request request,
    String conversationId,
    String itemId,
  ) async {
    return _toResponse(await handler.getItem(conversationId, itemId));
  });

  router.delete('/<conversationId>/items/<itemId>', (
    Request request,
    String conversationId,
    String itemId,
  ) async {
    return _toResponse(await handler.deleteItem(conversationId, itemId));
  });

  return router;
}

Future<Map<String, dynamic>> _readJson(Request request) async {
  final body = await request.readAsString();
  if (body.isEmpty) {
    return <String, dynamic>{};
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

Response _toResponse(ApiResult result) => Response(
  result.statusCode,
  body: result.body == null ? null : jsonEncode(result.body),
  headers: {'content-type': 'application/json'},
);
