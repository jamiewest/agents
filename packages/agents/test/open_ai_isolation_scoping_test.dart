// Copyright (c) Microsoft. All rights reserved.
//
// Covers the isolation-key scoping of the OpenAI hosting storage.

import 'package:agents/src/hosting/agent_isolation_key_provider.dart';
import 'package:agents/src/hosting/open_ai/conversations/in_memory_agent_conversation_index.dart';
import 'package:agents/src/hosting/open_ai/conversations/in_memory_conversation_storage.dart';
import 'package:agents/src/hosting/open_ai/conversations/isolation_key_scoped_agent_conversation_index.dart';
import 'package:agents/src/hosting/open_ai/conversations/isolation_key_scoped_conversation_storage.dart';
import 'package:agents/src/hosting/open_ai/conversations/models/conversation.dart';
import 'package:agents/src/hosting/open_ai/isolation_key_resolver.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('IsolationKeyResolver', () {
    test('escapes backslashes and colons in the key', () {
      expect(
        IsolationKeyResolver.scopeId('c1', r'tenant\region:alice'),
        r'tenant\\region\:alice::c1',
      );
    });

    test('round-trips a scoped id', () {
      final scoped = IsolationKeyResolver.scopeId('c1', 'alice');

      expect(IsolationKeyResolver.isInScope(scoped, 'alice'), isTrue);
      expect(IsolationKeyResolver.isInScope(scoped, 'bob'), isFalse);
      expect(IsolationKeyResolver.unscopeId(scoped, 'alice'), 'c1');
    });

    test('is a no-op without a key', () {
      expect(IsolationKeyResolver.scopeId('c1', null), 'c1');
      expect(IsolationKeyResolver.isInScope('c1', null), isTrue);
      expect(IsolationKeyResolver.unscopeId('c1', null), 'c1');
    });

    test('strict mode rejects a caller with no key', () {
      final resolver = IsolationKeyResolver(_KeyProvider(null), strict: true);

      expect(resolver.getKey(), throwsStateError);
    });
  });

  group('IsolationKeyScopedConversationStorage', () {
    test('one caller cannot resolve another caller\'s conversation', () async {
      final inner = InMemoryConversationStorage();
      final alice = _scopedStorage(inner, 'alice');
      final bob = _scopedStorage(inner, 'bob');

      final created = await alice.createConversation(
        Conversation(id: 'conv_1', createdAt: 0),
      );

      // The caller-visible id stays bare, so the wire format is unchanged.
      expect(created.id, 'conv_1');
      expect((await alice.getConversation('conv_1'))?.id, 'conv_1');
      expect(await bob.getConversation('conv_1'), isNull);
      expect(await bob.deleteConversation('conv_1'), isFalse);
    });

    test('is a pass-through when isolation is not configured', () async {
      final inner = InMemoryConversationStorage();
      final storage = IsolationKeyScopedConversationStorage(
        inner,
        IsolationKeyResolver(null, strict: false),
      );

      await storage.createConversation(
        Conversation(id: 'conv_1', createdAt: 0),
      );

      expect((await inner.getConversation('conv_1'))?.id, 'conv_1');
    });
  });

  group('IsolationKeyScopedAgentConversationIndex', () {
    test('lists only the caller\'s own conversations, unscoped', () async {
      final inner = InMemoryAgentConversationIndex();
      final alice = _scopedIndex(inner, 'alice');
      final bob = _scopedIndex(inner, 'bob');

      await alice.addConversation('agent-1', 'conv_a');
      await bob.addConversation('agent-1', 'conv_b');

      expect((await alice.getConversationIds('agent-1')).data, ['conv_a']);
      expect((await bob.getConversationIds('agent-1')).data, ['conv_b']);
    });

    test('removal is scoped too', () async {
      final inner = InMemoryAgentConversationIndex();
      final alice = _scopedIndex(inner, 'alice');
      final bob = _scopedIndex(inner, 'bob');

      await alice.addConversation('agent-1', 'conv_a');
      await bob.removeConversation('agent-1', 'conv_a');

      expect((await alice.getConversationIds('agent-1')).data, ['conv_a']);
    });
  });
}

IsolationKeyScopedConversationStorage _scopedStorage(
  InMemoryConversationStorage inner,
  String key,
) => IsolationKeyScopedConversationStorage(
  inner,
  IsolationKeyResolver(_KeyProvider(key), strict: true),
);

IsolationKeyScopedAgentConversationIndex _scopedIndex(
  InMemoryAgentConversationIndex inner,
  String key,
) => IsolationKeyScopedAgentConversationIndex(
  inner,
  IsolationKeyResolver(_KeyProvider(key), strict: true),
);

class _KeyProvider extends AgentIsolationKeyProvider {
  _KeyProvider(this._key);

  final String? _key;

  @override
  Future<String?> getIsolationKey({
    CancellationToken? cancellationToken,
  }) async => _key;
}
