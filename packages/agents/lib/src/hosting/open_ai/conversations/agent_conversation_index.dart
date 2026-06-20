// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Conversations/IAgentConversationIndex.cs.

import 'package:extensions/system.dart';

import '../models/list_response.dart';

/// Optional service for indexing conversations by agent ID.
///
/// A non-standard extension to the OpenAI Conversations API.
abstract interface class AgentConversationIndex {
  /// Adds a conversation to the index for [agentId].
  Future<void> addConversation(
    String agentId,
    String conversationId, {
    CancellationToken? cancellationToken,
  });

  /// Removes a conversation from the index for [agentId].
  Future<void> removeConversation(
    String agentId,
    String conversationId, {
    CancellationToken? cancellationToken,
  });

  /// Gets all conversation IDs indexed for [agentId].
  Future<ListResponse<String>> getConversationIds(
    String agentId, {
    CancellationToken? cancellationToken,
  });
}
