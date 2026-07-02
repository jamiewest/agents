// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Identifies the conversation (and optional channel) an agent instance is
/// being built for.
///
/// Passed to `ConfiguredAgentFactory.createAgent` so harness capabilities —
/// chat history, file stores, memory — can be wired to conversation-scoped
/// persistence by the application's scope configurator.
class AgentScope {
  /// Creates an [AgentScope].
  const AgentScope({
    required this.conversationId,
    required this.sessionIdResolver,
    this.channelId,
    this.isPrivate = false,
  });

  /// The conversation this agent instance serves.
  final String conversationId;

  /// The channel the conversation belongs to, when any.
  final String? channelId;

  /// Whether the conversation opted out of durable persistence.
  final bool isPrivate;

  /// Supplies the active session id for new writes.
  ///
  /// A conversation is one continuous transcript segmented into sessions
  /// (model-context epochs); this resolver returns the id of the session
  /// currently in progress.
  final String Function() sessionIdResolver;

  /// Derives a scope for a subordinate agent (for example a delegate),
  /// keeping its persisted state separate from the parent conversation.
  AgentScope child(String discriminator) => AgentScope(
    conversationId: '$conversationId#$discriminator',
    sessionIdResolver: sessionIdResolver,
    channelId: channelId,
    isPrivate: isPrivate,
  );
}
