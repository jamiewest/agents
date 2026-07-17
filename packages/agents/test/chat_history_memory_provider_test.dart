import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/ai_context.dart';
import 'package:agents/src/abstractions/agent_request_message_source_type.dart';
import 'package:agents/src/abstractions/chat_message_extensions.dart';
import 'package:agents/src/abstractions/invoked_context.dart';
import 'package:agents/src/abstractions/message_ai_context_provider.dart';
import 'package:agents/src/ai/memory/chat_history_memory_provider.dart';
import 'package:agents/src/ai/memory/chat_history_memory_provider_options.dart';
import 'package:agents/src/ai/memory/chat_history_memory_provider_scope.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:extensions/vector_data.dart';
import 'package:test/test.dart';
import 'package:agents/src/abstractions/invoking_context.dart';

void main() {
  const collectionName = 'testcollection';

  group('ChatHistoryMemoryProvider', () {
    test('constructor validates arguments and exposes state keys', () {
      final store = _FakeVectorStore();

      expect(
        () => ChatHistoryMemoryProvider(null, collectionName, 1, _state),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ChatHistoryMemoryProvider(store, null, 1, _state),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ChatHistoryMemoryProvider(store, ' ', 1, _state),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ChatHistoryMemoryProvider(store, collectionName, 0, _state),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ChatHistoryMemoryProvider(store, collectionName, 1, null),
        throwsA(isA<ArgumentError>()),
      );

      final provider = ChatHistoryMemoryProvider(
        store,
        collectionName,
        7,
        _state,
        options: ChatHistoryMemoryProviderOptions()..stateKey = 'custom-key',
      );

      expect(provider.stateKeys, ['custom-key']);
      expect(store.collectionName, collectionName);
      expect(
        store.definition!.vectorProperties
            .singleWhere(
              (p) =>
                  p.propertyName ==
                  ChatHistoryMemoryProvider.contentEmbeddingField,
            )
            .dimensions,
        7,
      );
    });

    test(
      'invoked stores request and response messages with scope fields',
      () async {
        final store = _FakeVectorStore();
        final scope = ChatHistoryMemoryProviderScope(
          applicationId: 'app1',
          agentId: 'agent1',
          sessionId: 'session1',
          userId: 'user1',
        );
        final provider = ChatHistoryMemoryProvider(
          store,
          collectionName,
          1,
          (_) => State(scope),
        );
        final session = _TestSession();
        final request = ChatMessage.fromText(ChatRole.user, 'request text')
          ..messageId = 'req-1'
          ..authorName = 'user1'
          ..createdAt = DateTime.utc(2000, 1, 1);
        final response =
            ChatMessage.fromText(ChatRole.assistant, 'response text')
              ..messageId = 'resp-1'
              ..authorName = 'assistant';

        await provider.invoked(
          InvokedContext(
            _TestAgent(),
            session,
            [request],
            responseMessages: [response],
          ),
        );

        expect(store.collection.ensureCount, 1);
        expect(store.collection.upserted, hasLength(2));
        expect(
          store.collection.upserted[0],
          containsPair('MessageId', 'req-1'),
        );
        expect(
          store.collection.upserted[0],
          containsPair('Content', 'request text'),
        );
        expect(store.collection.upserted[0], containsPair('Role', 'user'));
        expect(
          store.collection.upserted[0],
          containsPair('ApplicationId', 'app1'),
        );
        expect(store.collection.upserted[0], containsPair('AgentId', 'agent1'));
        expect(
          store.collection.upserted[0],
          containsPair('SessionId', 'session1'),
        );
        expect(store.collection.upserted[0], containsPair('UserId', 'user1'));
        expect(
          store.collection.upserted[1],
          containsPair('MessageId', 'resp-1'),
        );
        expect(
          store.collection.upserted[1],
          containsPair('Content', 'response text'),
        );
      },
    );

    test('invoked skips storage when invoke failed', () async {
      final store = _FakeVectorStore();
      final provider = ChatHistoryMemoryProvider(
        store,
        collectionName,
        1,
        _state,
      );

      await provider.invoked(
        InvokedContext(_TestAgent(), _TestSession(), [
          ChatMessage.fromText(ChatRole.user, 'request'),
        ], invokeException: Exception('failed')),
      );

      expect(store.collection.upserted, isEmpty);
    });

    test('invoking searches and injects formatted memory message', () async {
      final store = _FakeVectorStore()
        ..collection.searchResults.addAll([
          {
            ChatHistoryMemoryProvider.contentField: 'First stored message',
            ChatHistoryMemoryProvider.userIdField: 'UID',
          },
          {
            ChatHistoryMemoryProvider.contentField: 'Second stored message',
            ChatHistoryMemoryProvider.userIdField: 'UID',
          },
        ]);
      final provider = ChatHistoryMemoryProvider(
        store,
        collectionName,
        1,
        (_) => State(ChatHistoryMemoryProviderScope(userId: 'UID')),
        options: ChatHistoryMemoryProviderOptions()
          ..maxResults = 2
          ..contextPrompt = 'Here is the relevant chat history:',
      );
      final request = ChatMessage.fromText(
        ChatRole.user,
        'requesting relevant history',
      );

      final context = await provider.invoking(
        InvokingContext(
          _TestAgent(),
          _TestSession(),
          null,
          AIContext()..messages = [request],
        ),
      );
      final messages = context.messages!.toList();

      expect(store.collection.searchQuery, 'requesting relevant history');
      expect(store.collection.searchTop, 2);
      expect(messages, hasLength(2));
      expect(messages[1].text, contains('Here is the relevant chat history:'));
      expect(messages[1].text, contains('First stored message'));
      expect(
        messages[1].getAgentRequestMessageSourceType(),
        AgentRequestMessageSourceType.aiContextProvider,
      );
    });

    test('search scope filters vector records', () async {
      final store = _FakeVectorStore()
        ..collection.searchResults.addAll([
          {
            ChatHistoryMemoryProvider.contentField: 'match',
            ChatHistoryMemoryProvider.applicationIdField: 'app1',
            ChatHistoryMemoryProvider.agentIdField: 'agent1',
            ChatHistoryMemoryProvider.sessionIdField: 'session1',
            ChatHistoryMemoryProvider.userIdField: 'user1',
          },
          {
            ChatHistoryMemoryProvider.contentField: 'miss',
            ChatHistoryMemoryProvider.applicationIdField: 'app1',
            ChatHistoryMemoryProvider.agentIdField: 'agent1',
            ChatHistoryMemoryProvider.sessionIdField: 'other',
            ChatHistoryMemoryProvider.userIdField: 'user1',
          },
        ]);
      final scope = ChatHistoryMemoryProviderScope(
        applicationId: 'app1',
        agentId: 'agent1',
        sessionId: 'session1',
        userId: 'user1',
      );
      final provider = ChatHistoryMemoryProvider(
        store,
        collectionName,
        1,
        (_) => State(scope, searchScope: scope),
      );

      final results = await provider.searchChatHistory('query', scope, 10);

      expect(results.map((r) => r[ChatHistoryMemoryProvider.contentField]), [
        'match',
      ]);
      expect(store.collection.capturedFilter, isNotNull);
    });

    test(
      'default and custom filters control search and storage inputs',
      () async {
        final historyMessage = ChatMessage.fromText(ChatRole.system, 'history')
            .withAgentRequestMessageSource(
              AgentRequestMessageSourceType.chatHistory,
              sourceId: 'history',
            );
        final externalMessage = ChatMessage.fromText(ChatRole.user, 'external');

        final store = _FakeVectorStore();
        final provider = ChatHistoryMemoryProvider(
          store,
          collectionName,
          1,
          _state,
        );

        await provider.invoking(
          InvokingContext(
            _TestAgent(),
            _TestSession(),
            null,
            AIContext()..messages = [externalMessage, historyMessage],
          ),
        );
        expect(store.collection.searchQuery, 'external');

        await provider.invoked(
          InvokedContext(
            _TestAgent(),
            _TestSession(),
            [externalMessage, historyMessage],
            responseMessages: [
              ChatMessage.fromText(ChatRole.assistant, 'response'),
            ],
          ),
        );
        expect(store.collection.upserted.map((r) => r['Content']), [
          'external',
          'response',
        ]);

        final customStore = _FakeVectorStore();
        final customOptions = ChatHistoryMemoryProviderOptions();
        customOptions.searchInputMessageFilter = (messages) => messages;
        customOptions.storageInputRequestMessageFilter = (messages) => messages;
        final customProvider = ChatHistoryMemoryProvider(
          customStore,
          collectionName,
          1,
          _state,
          options: customOptions,
        );

        await customProvider.invoking(
          InvokingContext(
            _TestAgent(),
            _TestSession(),
            null,
            AIContext()..messages = [externalMessage, historyMessage],
          ),
        );
        expect(customStore.collection.searchQuery, contains('external'));
        expect(customStore.collection.searchQuery, contains('history'));
      },
    );

    test('on-demand mode exposes search tool', () async {
      final store = _FakeVectorStore()
        ..collection.searchResults.add({
          ChatHistoryMemoryProvider.contentField: 'remembered answer',
          ChatHistoryMemoryProvider.userIdField: 'UID',
        });
      final provider = ChatHistoryMemoryProvider(
        store,
        collectionName,
        1,
        _state,
        options: ChatHistoryMemoryProviderOptions()
          ..searchTime = SearchBehavior.onDemandFunctionCalling
          ..functionToolName = 'Memory_Search',
      );

      final context = await provider.provideAIContext(
        InvokingContext(
          _TestAgent(),
          _TestSession(),
          null,
          AIContext()..messages = [ChatMessage.fromText(ChatRole.user, 'Q?')],
        ),
      );
      final tool = context.tools!.single as AIFunction;
      final result = await tool.invoke(
        AIFunctionArguments({'userQuestion': 'Who am I?'}),
      );

      expect(tool.name, 'Memory_Search');
      expect(result, contains('remembered answer'));
    });

    test('message invoking throws in on-demand mode', () async {
      final provider = ChatHistoryMemoryProvider(
        _FakeVectorStore(),
        collectionName,
        1,
        _state,
        options: ChatHistoryMemoryProviderOptions()
          ..searchTime = SearchBehavior.onDemandFunctionCalling,
      );

      expect(
        () => provider.invokingMessages(
          MessageInvokingContext(_TestAgent(), _TestSession(), [
            ChatMessage.fromText(ChatRole.user, 'Q?'),
          ]),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('dispose is idempotent and blocks later initialization', () async {
      final provider = ChatHistoryMemoryProvider(
        _FakeVectorStore(),
        collectionName,
        1,
        _state,
      );

      provider.dispose();
      provider.dispose();

      expect(
        () => provider.ensureCollectionExists(),
        throwsA(isA<StateError>()),
      );
    });
  });
}

State _state(AgentSession? session) =>
    State(ChatHistoryMemoryProviderScope(userId: 'UID'));

class _FakeVectorStore extends VectorStore {
  final _FakeVectorStoreCollection collection = _FakeVectorStoreCollection();
  String? collectionName;
  VectorStoreCollectionDefinition? definition;

  @override
  VectorStoreCollection<TKey, TRecord> getCollection<TKey, TRecord>(
    String name, {
    VectorStoreCollectionDefinition? definition,
  }) => throw UnimplementedError();

  @override
  VectorStoreCollection<String, Map<String, Object?>> getDynamicCollection(
    String name,
    VectorStoreCollectionDefinition definition,
  ) {
    collectionName = name;
    this.definition = definition;
    return collection;
  }

  @override
  Stream<String> listCollectionNamesAsync({
    CancellationToken? cancellationToken,
  }) => Stream.fromIterable([?collectionName]);

  @override
  Future<bool> collectionExistsAsync(
    String name, {
    CancellationToken? cancellationToken,
  }) async => name == collectionName;

  @override
  Future<void> ensureCollectionDeletedAsync(
    String name, {
    CancellationToken? cancellationToken,
  }) async {}
}

class _FakeVectorStoreCollection
    extends VectorStoreCollection<String, Map<String, Object?>> {
  final List<Map<String, Object?>> upserted = [];
  final List<Map<String, Object?>> searchResults = [];
  bool throwOnUpsert = false;
  bool disposed = false;
  int ensureCount = 0;
  String? searchQuery;
  int? searchTop;
  VectorStoreFilter? capturedFilter;

  @override
  String get name => 'fake';

  @override
  Future<bool> collectionExistsAsync({
    CancellationToken? cancellationToken,
  }) async => ensureCount > 0;

  @override
  Future<void> ensureCollectionExistsAsync({
    CancellationToken? cancellationToken,
  }) async {
    ensureCount++;
  }

  @override
  Future<void> ensureCollectionDeletedAsync({
    CancellationToken? cancellationToken,
  }) async {}

  @override
  Future<Map<String, Object?>?> getAsync(
    String key, {
    RecordRetrievalOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    for (final record in upserted) {
      if (record['Key'] == key) {
        return record;
      }
    }
    return null;
  }

  @override
  Stream<Map<String, Object?>> getBatchAsync(
    Iterable<String> keys, {
    RecordRetrievalOptions? options,
    CancellationToken? cancellationToken,
  }) => Stream.fromIterable(
    upserted.where((record) => keys.contains(record['Key'])),
  );

  @override
  Stream<Map<String, Object?>> getFilteredAsync({
    VectorStoreFilter? filter,
    int? top,
    FilteredRecordRetrievalOptions<Map<String, Object?>>? options,
    CancellationToken? cancellationToken,
  }) {
    final matches = upserted.where((record) => _matches(filter, record));
    return Stream.fromIterable(top == null ? matches : matches.take(top));
  }

  @override
  Future<String> upsertAsync(
    Map<String, Object?> record, {
    CancellationToken? cancellationToken,
  }) async {
    if (throwOnUpsert) {
      throw StateError('Upsert failed');
    }
    upserted.add(Map<String, Object?>.of(record));
    return record['Key']! as String;
  }

  @override
  Stream<String> upsertBatchAsync(
    Iterable<Map<String, Object?>> records, {
    CancellationToken? cancellationToken,
  }) async* {
    for (final record in records) {
      yield await upsertAsync(record, cancellationToken: cancellationToken);
    }
  }

  @override
  Future<void> deleteAsync(
    String key, {
    CancellationToken? cancellationToken,
  }) async {
    upserted.removeWhere((record) => record['Key'] == key);
  }

  @override
  Future<void> deleteBatchAsync(
    Iterable<String> keys, {
    CancellationToken? cancellationToken,
  }) async {
    upserted.removeWhere((record) => keys.contains(record['Key']));
  }

  @override
  Stream<VectorSearchResult<Map<String, Object?>>> searchAsync<TInput>(
    TInput value, {
    int top = 3,
    VectorSearchOptions<Map<String, Object?>>? options,
    CancellationToken? cancellationToken,
  }) async* {
    searchQuery = value.toString();
    searchTop = top;
    capturedFilter = options?.filter;

    final filtered = searchResults
        .where((record) => _matches(options?.filter, record))
        .take(top);
    for (final record in filtered) {
      yield VectorSearchResult(record, score: 1.0);
    }
  }

  bool _matches(VectorStoreFilter? filter, Map<String, Object?> record) =>
      switch (filter) {
        null => true,
        EqualToVectorStoreFilter(:final fieldName, :final value) =>
          record[fieldName] == value,
        AnyTagEqualToVectorStoreFilter(:final fieldName, :final value) =>
          switch (record[fieldName]) {
            final Iterable<Object?> tags => tags.contains(value),
            _ => false,
          },
        AndVectorStoreFilter(:final filters) => filters.every(
          (child) => _matches(child, record),
        ),
        OrVectorStoreFilter(:final filters) => filters.any(
          (child) => _matches(child, record),
        ),
      };

  @override
  void dispose() {
    disposed = true;
  }
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
  }) async => {};

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
