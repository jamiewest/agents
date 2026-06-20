// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Conversations/InMemoryAgentConversationIndex.cs.
//
// Uses a plain in-memory map (see the note in InMemoryConversationStorage).

import 'package:extensions/system.dart';

import '../models/list_response.dart';
import 'agent_conversation_index.dart';

/// In-memory [AgentConversationIndex] for development and testing.
class InMemoryAgentConversationIndex implements AgentConversationIndex {
  final Map<String, Set<String>> _index = {};

  @override
  Future<void> addConversation(
    String agentId,
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async {
    _index.putIfAbsent(agentId, () => <String>{}).add(conversationId);
  }

  @override
  Future<void> removeConversation(
    String agentId,
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async {
    _index[agentId]?.remove(conversationId);
  }

  @override
  Future<ListResponse<String>> getConversationIds(
    String agentId, {
    CancellationToken? cancellationToken,
  }) async {
    final ids = _index[agentId]?.toList() ?? const <String>[];
    return ListResponse<String>(data: ids, hasMore: false);
  }
}
