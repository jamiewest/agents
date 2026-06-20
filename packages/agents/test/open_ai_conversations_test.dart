// Copyright (c) Microsoft. All rights reserved.

import 'package:agents/src/hosting/open_ai/conversations/conversations_handler.dart';
import 'package:agents/src/hosting/open_ai/conversations/in_memory_agent_conversation_index.dart';
import 'package:agents/src/hosting/open_ai/conversations/in_memory_conversation_storage.dart';
import 'package:agents/src/hosting/open_ai/conversations/models/create_conversation_request.dart';
import 'package:agents/src/hosting/open_ai/conversations/models/create_items_request.dart';
import 'package:agents/src/hosting/open_ai/conversations/models/update_conversation_request.dart';
import 'package:agents/src/hosting/open_ai/id_generator.dart';
import 'package:agents/src/hosting/open_ai/responses/models/item_param.dart';
import 'package:agents/src/hosting/open_ai/responses/models/item_resource.dart';
import 'package:test/test.dart';

void main() {
  group('ItemParam.toItemResource', () {
    test('assigns an ID and a completed status for messages', () {
      final param = ItemParam.fromJson({
        'type': 'message',
        'role': 'user',
        'content': 'hello',
      });
      final resource = param.toItemResource(IdGenerator(randomSeed: 1));

      expect(resource.id, isNotEmpty);
      expect(resource.type, 'message');
      final json = resource.toJson();
      expect(json['status'], 'completed');
      expect(json['content'], 'hello');
    });

    test('round-trips an exotic item type losslessly', () {
      final param = ItemParam.fromJson({
        'type': 'web_search_call',
        'action': {'query': 'dart'},
      });
      final resource = param.toItemResource(IdGenerator(randomSeed: 1));
      expect(resource.type, 'web_search_call');
      expect(resource.toJson()['action'], {'query': 'dart'});
      // No status added for non-message/function types.
      expect(resource.toJson().containsKey('status'), isFalse);
    });
  });

  group('ConversationsHandler', () {
    late InMemoryConversationStorage storage;
    late InMemoryAgentConversationIndex index;
    late ConversationsHandler handler;

    setUp(() {
      storage = InMemoryConversationStorage();
      index = InMemoryAgentConversationIndex();
      handler = ConversationsHandler(storage, index);
    });

    test('create → get → update → delete lifecycle', () async {
      final created = await handler.createConversation(
        CreateConversationRequest.fromJson({
          'metadata': {'agent_id': 'agent-1', 'topic': 'greeting'},
        }),
      );
      expect(created.statusCode, 200);
      final id = (created.body as Map)['id'] as String;
      expect((created.body as Map)['object'], 'conversation');

      // Indexed by agent.
      final listed = await handler.listConversationsByAgent('agent-1');
      final listedData = (listed.body as Map)['data'] as List;
      expect(listedData, hasLength(1));

      final fetched = await handler.getConversation(id);
      expect(fetched.statusCode, 200);

      final updated = await handler.updateConversation(
        id,
        UpdateConversationRequest.fromJson({
          'metadata': {'topic': 'farewell'},
        }),
      );
      expect((updated.body as Map)['metadata'], {'topic': 'farewell'});

      final deleted = await handler.deleteConversation(id);
      expect((deleted.body as Map)['object'], 'conversation.deleted');
      expect((await handler.getConversation(id)).statusCode, 404);
      expect(
        ((await handler.listConversationsByAgent('agent-1')).body
            as Map)['data'],
        isEmpty,
      );
    });

    test('items: create, list with pagination, get, delete', () async {
      final created = await handler.createConversation(
        CreateConversationRequest.fromJson(const {}),
      );
      final id = (created.body as Map)['id'] as String;

      // Add three user messages.
      await handler.createItems(
        id,
        CreateItemsRequest.fromJson({
          'items': [
            {'type': 'message', 'role': 'user', 'content': 'one'},
            {'type': 'message', 'role': 'user', 'content': 'two'},
            {'type': 'message', 'role': 'user', 'content': 'three'},
          ],
        }),
      );

      // Default order is descending (newest first), limit 2 → has_more.
      final firstPage = await handler.listItems(id, limit: 2);
      final firstBody = firstPage.body as Map;
      expect((firstBody['data'] as List), hasLength(2));
      expect(firstBody['has_more'], isTrue);
      final cursor = firstBody['last_id'] as String;

      final secondPage = await handler.listItems(id, limit: 2, after: cursor);
      final secondBody = secondPage.body as Map;
      expect((secondBody['data'] as List), hasLength(1));
      expect(secondBody['has_more'], isFalse);

      // Get a specific item.
      final anItemId =
          ((firstBody['data'] as List).first as Map)['id'] as String;
      final gotItem = await handler.getItem(id, anItemId);
      expect(gotItem.statusCode, 200);

      // Delete it.
      final del = await handler.deleteItem(id, anItemId);
      expect((del.body as Map)['object'], 'conversation.item.deleted');
      expect((await handler.getItem(id, anItemId)).statusCode, 404);
    });

    test('ascending order returns items oldest-first', () async {
      final created = await handler.createConversation(
        CreateConversationRequest.fromJson(const {}),
      );
      final id = (created.body as Map)['id'] as String;
      await handler.createItems(
        id,
        CreateItemsRequest.fromJson({
          'items': [
            {'type': 'message', 'role': 'user', 'content': 'first'},
            {'type': 'message', 'role': 'user', 'content': 'second'},
          ],
        }),
      );

      final asc = await handler.listItems(id, order: 'asc');
      final data = (asc.body as Map)['data'] as List;
      expect((data.first as Map)['content'], 'first');
    });

    test('missing conversation yields 404', () async {
      expect((await handler.getConversation('conv_missing')).statusCode, 404);
      expect((await handler.listItems('conv_missing')).statusCode, 404);
    });

    test('listItems rejects non-positive limit', () async {
      final created = await handler.createConversation(
        CreateConversationRequest.fromJson(const {}),
      );
      final id = (created.body as Map)['id'] as String;
      final result = await handler.listItems(id, limit: 0);
      expect(result.statusCode, 400);
    });
  });

  test('storage stores items as ItemResource', () async {
    final storage = InMemoryConversationStorage();
    final resource = ItemResource.fromJson({
      'id': 'msg_1',
      'type': 'message',
      'role': 'user',
      'content': 'hi',
    });
    await storage.addItems('conv_x', [resource]);
    // No conversation created → addItems is a no-op (matches handler guard).
    expect(await storage.getItem('conv_x', 'msg_1'), isNull);
  });
}
