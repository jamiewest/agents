// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: non_constant_identifier_names

import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:extensions/vector_data.dart';
import 'package:flutter_test/flutter_test.dart';

VectorStoreCollectionDefinition _definition() =>
    VectorStoreCollectionDefinition(
      properties: [
        VectorStoreKeyProperty('Key'),
        VectorStoreDataProperty('AgentId')..isIndexed = true,
        VectorStoreDataProperty('Content'),
        VectorStoreVectorProperty('ContentEmbedding', dimensions: 3),
      ],
    );

Map<String, Object?> _record(String key, String agentId, String text) => {
  'Key': key,
  'AgentId': agentId,
  'Content': text,
  'ContentEmbedding': text,
};

void main() {
  group('KeywordOverlapScorer', () {
    const scorer = KeywordOverlapScorer();

    test('scores shared words higher and stores no vectors', () async {
      expect(await scorer.embed('anything'), isNull);
      final related = scorer.score(
        queryText: 'the weather in seattle',
        recordText: 'seattle weather is rainy',
      );
      final unrelated = scorer.score(
        queryText: 'the weather in seattle',
        recordText: 'quarterly finance report',
      );
      expect(related, greaterThan(unrelated));
      expect(unrelated, 0);
    });
  });

  group('EmbeddingGeneratorScorer.cosineSimilarity', () {
    test('is 1 for parallel, 0 for orthogonal or mismatched', () {
      expect(
        EmbeddingGeneratorScorer.cosineSimilarity([1, 0], [2, 0]),
        closeTo(1, 1e-9),
      );
      expect(EmbeddingGeneratorScorer.cosineSimilarity([1, 0], [0, 1]), 0);
      expect(EmbeddingGeneratorScorer.cosineSimilarity([1, 0], [1]), 0);
    });
  });

  group('RecordStoreVectorStore', () {
    late InMemoryRecordStore records;

    setUp(() => records = InMemoryRecordStore());

    VectorStoreCollection<String, Map<String, Object?>> collection({
      MemoryScorer? scorer,
    }) => RecordStoreVectorStore(
      records,
      scorer: scorer,
    ).getDynamicCollection('chat_memory', _definition());

    test('upserts and searches with scope filtering', () async {
      final target = collection();
      await target.ensureCollectionExistsAsync();
      await target.upsertBatchAsync([
        _record('1', 'agent-a', 'my favorite color is teal'),
        _record('2', 'agent-a', 'the deploy pipeline uses github'),
        _record('3', 'agent-b', 'favorite color of the user is red'),
      ]).drain<void>();

      final results = await target
          .searchAsync(
            'what is my favorite color?',
            top: 2,
            options: VectorSearchOptions(
              filter: VectorStoreFilter.equalTo('AgentId', 'agent-a'),
            ),
          )
          .toList();

      expect(results.first.record['Key'], '1');
      // agent-b's memory never appears, even though it matches better than
      // agent-a's unrelated record.
      expect(results.map((result) => result.record['AgentId']).toSet(), {
        'agent-a',
      });
    });

    test('and-filters translate to combined equality', () async {
      final target = collection();
      await target.upsertAsync(_record('1', 'agent-a', 'note'));

      final results = await target
          .searchAsync(
            'note',
            options: VectorSearchOptions(
              filter: VectorStoreFilter.and([
                VectorStoreFilter.equalTo('AgentId', 'agent-a'),
                VectorStoreFilter.equalTo('Key', '1'),
              ]),
            ),
          )
          .toList();

      expect(results, hasLength(1));
    });

    test('or filters are unsupported', () async {
      final target = collection();

      expect(
        () => target
            .searchAsync(
              'x',
              options: VectorSearchOptions(
                filter: VectorStoreFilter.or([
                  VectorStoreFilter.equalTo('AgentId', 'a'),
                ]),
              ),
            )
            .toList(),
        throwsUnsupportedError,
      );
    });

    test('embedding scorer stores vectors and ranks by cosine', () async {
      final target = collection(scorer: _FakeEmbeddingScorer());
      await target.upsertAsync(_record('hot', 'a', 'sun'));
      await target.upsertAsync(_record('cold', 'a', 'ice'));

      final results = await target.searchAsync('sunny', top: 2).toList();

      expect(results.first.record['Key'], 'hot');
      expect(results.first.score, greaterThan(results.last.score!));
      // Vectors stay internal.
      expect(results.first.record.containsKey('_vector'), isFalse);
      expect((await target.getAsync('hot'))!.containsKey('_vector'), isFalse);
    });

    test('persists across store instances over the same records', () async {
      await collection().upsertAsync(_record('1', 'a', 'remember me'));

      final reopened = await collection().searchAsync('remember').toList();

      expect(reopened.single.record['Content'], 'remember me');
    });

    test('collection registry tracks existence and deletion', () async {
      final store = RecordStoreVectorStore(records);
      final target = store.getDynamicCollection('chat_memory', _definition());
      await target.ensureCollectionExistsAsync();
      await target.upsertAsync(_record('1', 'a', 'x'));

      expect(await store.collectionExistsAsync('chat_memory'), isTrue);
      await store.ensureCollectionDeletedAsync('chat_memory');
      expect(await store.collectionExistsAsync('chat_memory'), isFalse);
      expect(await target.getAsync('1'), isNull);
    });
  });

  group('ChatHistoryMemoryProvider over RecordStoreVectorStore', () {
    test('recalls one agent\'s memories and never another\'s', () async {
      final records = InMemoryRecordStore();

      ChatHistoryMemoryProvider providerFor(String agentId) =>
          ChatHistoryMemoryProvider(
            RecordStoreVectorStore(records),
            'chat_memory',
            3,
            (_) => ChatHistoryMemoryProviderState(
              ChatHistoryMemoryProviderScope(
                applicationId: 'agents_app',
                agentId: agentId,
                sessionId: 'conv-1',
              ),
            ),
          );

      // Distinct sessions: provider scope state lives in the session bag.
      final agent = _TestAgent();
      await providerFor('agent-a').invoked(
        InvokedContext(agent, _TestSession(), [
          ChatMessage.fromText(ChatRole.user, 'my cat is named Miso'),
        ], responseMessages: const []),
      );
      await providerFor('agent-b').invoked(
        InvokedContext(agent, _TestSession(), [
          ChatMessage.fromText(ChatRole.user, 'my cat is named Ollie'),
        ], responseMessages: const []),
      );

      final recalledByA = await providerFor('agent-a').searchChatHistory(
        'what is my cat named?',
        ChatHistoryMemoryProviderScope(
          applicationId: 'agents_app',
          agentId: 'agent-a',
          sessionId: 'conv-1',
        ),
        5,
      );

      final contents = recalledByA.map((r) => r['Content']).toList();
      expect(contents, contains('my cat is named Miso'));
      expect(contents, isNot(contains('my cat is named Ollie')));
    });
  });
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

class _TestAgent extends AIAgent {
  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => <String, Object?>{};

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async =>
      AgentResponse(message: ChatMessage.fromText(ChatRole.assistant, 'ok'));

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {}
}

/// Deterministic embedder: 'sun'-ish text maps near [1,0,0]; 'ice'-ish near
/// [0,1,0].
final class _FakeEmbeddingScorer extends MemoryScorer {
  @override
  Future<List<double>?> embed(String text) async =>
      text.contains('sun') ? [1, 0, 0] : [0, 1, 0];

  @override
  double score({
    required String queryText,
    required String recordText,
    List<double>? queryVector,
    List<double>? recordVector,
  }) => EmbeddingGeneratorScorer.cosineSimilarity(
    queryVector ?? const [],
    recordVector ?? const [],
  );
}
