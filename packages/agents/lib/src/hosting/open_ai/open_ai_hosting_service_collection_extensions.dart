// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ServiceCollectionExtensions.cs.
//
// The C# methods primarily register JSON `TypeInfoResolver`s into ASP.NET's
// `JsonOptions`. This port controls (de)serialization explicitly via each
// model's `fromJson`/`toJson`, so the chat-completions registration is a no-op
// marker retained for API parity and discoverability. The Conversations and
// Responses registrations are added as those surfaces are ported.

import 'package:extensions/dependency_injection.dart';

import 'conversations/agent_conversation_index.dart';
import 'conversations/conversation_storage.dart';
import 'conversations/in_memory_agent_conversation_index.dart';
import 'conversations/in_memory_conversation_storage.dart';
import 'in_memory_storage_options.dart';

/// OpenAI-hosting registration helpers for a [ServiceCollection].
extension OpenAIHostingServiceCollectionExtensions on ServiceCollection {
  /// Adds support for exposing agents via OpenAI Chat Completions.
  ///
  /// Serialization is handled per-model in this port, so registration performs
  /// no container changes; it exists for parity with the upstream API and as
  /// the documented entry point. Mount the chat-completions router to serve
  /// traffic.
  ServiceCollection addOpenAIChatCompletions() => this;

  /// Adds in-memory conversation storage and indexing services.
  ///
  /// Suitable only for development and testing. Mount the conversations router
  /// to serve traffic.
  ServiceCollection addOpenAIConversations() {
    tryAddSingleton<InMemoryStorageOptions>((sp) => InMemoryStorageOptions());
    tryAddSingleton<ConversationStorage>((sp) => InMemoryConversationStorage());
    tryAddSingleton<AgentConversationIndex>(
      (sp) => InMemoryAgentConversationIndex(),
    );
    return this;
  }

  /// Adds the shared in-memory storage used by the OpenAI Responses API.
  ///
  /// Registers the conversation storage/index used for conversation-linked
  /// responses. The per-agent `ResponseExecutor`/`ResponsesService` are
  /// constructed by the host when mounting the responses router (they are
  /// scoped to a specific agent), so they are not registered here.
  ServiceCollection addOpenAIResponses() => addOpenAIConversations();
}
