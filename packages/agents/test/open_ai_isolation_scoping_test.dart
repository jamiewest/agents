// Copyright (c) Microsoft. All rights reserved.
//
// Ported in spirit from the isolation-scoping tests added with upstream #8146.

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
  Conversation conversation(String id) =>
      Conversation(id: id, createdAt: 1700000000);

  group('IsolationKeyResolver', () {
    test('scopes and unscopes round-trip', () async {
      expect(IsolationKeyResolver.scopeId('c1', 'tenant-a'), 'tenant-a::c1');
      expect(IsolationKeyResolver.unscopeId('tenant-a::c1', 'tenant-a'), 'c1');
      expect(
        IsolationKeyResolver.isInScope('tenant-a::c1', 'tenant-a'),
        isTrue,
      );
      expect(
        IsolationKeyResolver.isInScope('tenant-b::c1', 'tenant-a'),
        isFalse,
      );
    });

    test('escapes backslashes and colons in the key', () {
      expect(
        IsolationKeyResolver.scopeId('c1', r'tenant\region:alice'),
        r'tenant\\region\:alice::c1',
      );
    });

    test('passes identifiers through when no provider is configured', () async {
      final resolver = IsolationKeyResolver(null);

      expect(await resolver.getKey(), isNull);
      expect(await resolver.scopeIdAsync('c1'), 'c1');
      expect(IsolationKeyResolver.scopeId('c1', null), 'c1');
      expect(IsolationKeyResolver.unscopeId('c1', null), 'c1');
      expect(IsolationKeyResolver.isInScope('anything', null), isTrue);
    });

    test('throws in strict mode when the key is unavailable', () {
      final resolver = IsolationKeyResolver(
        _FixedKeyProvider(null),
        strict: true,
      );

      expect(resolver.getKey(), throwsStateError);
    });

    test(
      'passes through in non-strict mode when the key is unavailable',
      () async {
        final resolver = IsolationKeyResolver(_FixedKeyProvider(null));

        expect(await resolver.scopeIdAsync('c1'), 'c1');
      },
    );
  });

  group('IsolationKeyScopedConversationStorage', () {
    test('scopes the storage key but reports the bare id', () async {
      final inner = InMemoryConversationStorage();
      final storage = IsolationKeyScopedConversationStorage(
        inner,
        IsolationKeyResolver(_FixedKeyProvider('tenant-a')),
      );

      final created = await storage.createConversation(conversation('c1'));

      expect(created.id, 'c1');
      expect(await inner.getConversation('tenant-a::c1'), isNotNull);
      expect(await inner.getConversation('c1'), isNull);
    });

    test('one caller cannot resolve another caller\'s conversation', () async {
      final inner = InMemoryConversationStorage();
      final a = IsolationKeyScopedConversationStorage(
        inner,
        IsolationKeyResolver(_FixedKeyProvider('tenant-a')),
      );
      final b = IsolationKeyScopedConversationStorage(
        inner,
        IsolationKeyResolver(_FixedKeyProvider('tenant-b')),
      );

      await a.createConversation(conversation('c1'));

      expect(await a.getConversation('c1'), isNotNull);
      expect(await b.getConversation('c1'), isNull);
      expect(await b.deleteConversation('c1'), isFalse);
    });

    test('scopes item operations too', () async {
      final inner = InMemoryConversationStorage();
      final a = IsolationKeyScopedConversationStorage(
        inner,
        IsolationKeyResolver(_FixedKeyProvider('tenant-a')),
      );
      final b = IsolationKeyScopedConversationStorage(
        inner,
        IsolationKeyResolver(_FixedKeyProvider('tenant-b')),
      );

      await a.createConversation(conversation('c1'));
      await b.createConversation(conversation('c1'));

      expect((await a.listItems('c1')).data, isEmpty);
      expect((await b.listItems('c1')).data, isEmpty);
    });
  });

  group('IsolationKeyScopedAgentConversationIndex', () {
    test('returns only the caller\'s conversations, bare', () async {
      final inner = InMemoryAgentConversationIndex();
      final a = IsolationKeyScopedAgentConversationIndex(
        inner,
        IsolationKeyResolver(_FixedKeyProvider('tenant-a')),
      );
      final b = IsolationKeyScopedAgentConversationIndex(
        inner,
        IsolationKeyResolver(_FixedKeyProvider('tenant-b')),
      );

      await a.addConversation('agent-1', 'c1');
      await b.addConversation('agent-1', 'c2');

      expect((await a.getConversationIds('agent-1')).data, ['c1']);
      expect((await b.getConversationIds('agent-1')).data, ['c2']);
    });

    test('removes only the caller\'s own entry', () async {
      final inner = InMemoryAgentConversationIndex();
      final a = IsolationKeyScopedAgentConversationIndex(
        inner,
        IsolationKeyResolver(_FixedKeyProvider('tenant-a')),
      );
      final b = IsolationKeyScopedAgentConversationIndex(
        inner,
        IsolationKeyResolver(_FixedKeyProvider('tenant-b')),
      );

      await a.addConversation('agent-1', 'c1');
      await b.addConversation('agent-1', 'c1');

      await b.removeConversation('agent-1', 'c1');

      expect((await a.getConversationIds('agent-1')).data, ['c1']);
      expect((await b.getConversationIds('agent-1')).data, isEmpty);
    });

    test('sets firstId and lastId from the filtered list', () async {
      final inner = InMemoryAgentConversationIndex();
      final a = IsolationKeyScopedAgentConversationIndex(
        inner,
        IsolationKeyResolver(_FixedKeyProvider('tenant-a')),
      );

      await a.addConversation('agent-1', 'c1');
      await a.addConversation('agent-1', 'c2');

      final ids = await a.getConversationIds('agent-1');

      expect(ids.data, ['c1', 'c2']);
      expect(ids.firstId, 'c1');
      expect(ids.lastId, 'c2');
    });
  });
}

class _FixedKeyProvider extends AgentIsolationKeyProvider {
  _FixedKeyProvider(this._key);

  final String? _key;

  @override
  Future<String?> getIsolationKey({
    CancellationToken? cancellationToken,
  }) async => _key;
}
