// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Conversations/IsolationKeyScopedAgentConversationIndex.cs.

import 'package:extensions/system.dart';

import '../isolation_key_resolver.dart';
import '../models/list_response.dart';
import 'agent_conversation_index.dart';

/// A delegating [AgentConversationIndex] that scopes indexed conversation
/// identifiers by the caller's isolation key, so that listing conversations
/// for an agent returns only the caller's own conversations.
///
/// The index is keyed by the bare agent identifier, so the underlying store
/// holds one entry per agent rather than one per caller-agent pair.
/// Conversation identifiers held in that entry are scoped, filtered for the
/// current caller, and returned bare.
class IsolationKeyScopedAgentConversationIndex
    implements AgentConversationIndex {
  /// Creates an index decorator that scopes ids through [resolver].
  IsolationKeyScopedAgentConversationIndex(this._innerIndex, this._resolver);

  final AgentConversationIndex _innerIndex;
  final IsolationKeyResolver _resolver;

  @override
  Future<void> addConversation(
    String agentId,
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async {
    final scopedConversationId = await _resolver.scopeIdAsync(
      conversationId,
      cancellationToken: cancellationToken,
    );
    await _innerIndex.addConversation(
      agentId,
      scopedConversationId,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<void> removeConversation(
    String agentId,
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async {
    final scopedConversationId = await _resolver.scopeIdAsync(
      conversationId,
      cancellationToken: cancellationToken,
    );
    await _innerIndex.removeConversation(
      agentId,
      scopedConversationId,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<ListResponse<String>> getConversationIds(
    String agentId, {
    CancellationToken? cancellationToken,
  }) async {
    final key = await _resolver.getKey(cancellationToken: cancellationToken);
    final response = await _innerIndex.getConversationIds(
      agentId,
      cancellationToken: cancellationToken,
    );

    if (key == null) {
      return response;
    }

    final conversationIds = <String>[
      for (final scopedConversationId in response.data)
        if (IsolationKeyResolver.isInScope(scopedConversationId, key))
          IsolationKeyResolver.unscopeId(scopedConversationId, key),
    ];

    return ListResponse<String>(
      data: conversationIds,
      firstId: conversationIds.isNotEmpty ? conversationIds.first : null,
      lastId: conversationIds.isNotEmpty ? conversationIds.last : null,
      hasMore: response.hasMore,
    );
  }
}
