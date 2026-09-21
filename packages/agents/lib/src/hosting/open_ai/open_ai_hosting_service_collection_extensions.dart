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

import '../agent_isolation_key_provider.dart';
import 'conversations/agent_conversation_index.dart';
import 'conversations/conversation_storage.dart';
import 'conversations/in_memory_agent_conversation_index.dart';
import 'conversations/in_memory_conversation_storage.dart';
import 'conversations/isolation_key_scoped_agent_conversation_index.dart';
import 'conversations/isolation_key_scoped_conversation_storage.dart';
import 'in_memory_storage_options.dart';
import 'isolation_key_resolver.dart';

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
  ///
  /// Conversation identifiers are scoped by the registered
  /// [AgentIsolationKeyProvider] when there is one. Hosts serving multiple
  /// callers should register a provider, require authentication on the mounted
  /// routes, and use a stable claim that uniquely identifies the caller.
  /// Without a provider, all callers share the same in-memory namespace.
  ServiceCollection addOpenAIConversations() {
    tryAddSingleton<InMemoryStorageOptions>((sp) => InMemoryStorageOptions());
    tryAddSingleton<ConversationStorage>((sp) {
      final resolver = createIsolationKeyResolver(sp);
      final storage = InMemoryConversationStorage();
      return resolver == null
          ? storage
          : IsolationKeyScopedConversationStorage(storage, resolver);
    });
    tryAddSingleton<AgentConversationIndex>((sp) {
      final resolver = createIsolationKeyResolver(sp);
      final index = InMemoryAgentConversationIndex();
      return resolver == null
          ? index
          : IsolationKeyScopedAgentConversationIndex(index, resolver);
    });
    return this;
  }

  /// Adds the shared in-memory storage used by the OpenAI Responses API.
  ///
  /// Registers the conversation storage/index used for conversation-linked
  /// responses. The per-agent `ResponseExecutor`/`ResponsesService` are
  /// constructed by the host when mounting the responses router (they are
  /// scoped to a specific agent), so they are not registered here. Pass
  /// [createIsolationKeyResolver] to the `InMemoryResponsesService` so stored
  /// responses are scoped the same way the conversation storage is.
  ServiceCollection addOpenAIResponses() => addOpenAIConversations();
}

/// Builds the [IsolationKeyResolver] for a host from the registered
/// [AgentIsolationKeyProvider], or returns `null` when isolation is not
/// configured.
///
/// The resolver is strict when a provider is registered: a caller whose key
/// cannot be determined is an error rather than a caller that silently shares
/// the unscoped namespace.
IsolationKeyResolver? createIsolationKeyResolver(ServiceProvider services) {
  final provider = services.getService<AgentIsolationKeyProvider>();
  return provider == null ? null : IsolationKeyResolver(provider, strict: true);
}
