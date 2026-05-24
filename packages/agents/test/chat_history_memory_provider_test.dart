// ignore_for_file: non_constant_identifier_names

import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/ai_context.dart';
import 'package:agents/src/abstractions/ai_context_provider.dart';
import 'package:agents/src/abstractions/agent_request_message_source_type.dart';
import 'package:agents/src/abstractions/chat_message_extensions.dart';
import 'package:agents/src/abstractions/message_ai_context_provider.dart';
import 'package:agents/src/ai/memory/chat_history_memory_provider.dart';
import 'package:agents/src/ai/memory/chat_history_memory_provider_options.dart';
import 'package:agents/src/ai/memory/chat_history_memory_provider_scope.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

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
        store.definition!.properties
            .singleWhere(
              (p) => p.name == ChatHistoryMemoryProvider.contentEmbeddingField,
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

class _FakeVectorStore implements VectorStore {
  final _FakeVectorStoreCollection collection = _FakeVectorStoreCollection();
  String? collectionName;
  VectorStoreCollectionDefinition? definition;

  @override
  VectorStoreCollection<Object, Map<String, Object?>> getDynamicCollection(
    String collectionName,
    VectorStoreCollectionDefinition definition,
  ) {
    this.collectionName = collectionName;
    this.definition = definition;
    return collection;
  }
}

class _FakeVectorStoreCollection
    implements VectorStoreCollection<Object, Map<String, Object?>> {
  final List<Map<String, Object?>> upserted = [];
  final List<Map<String, Object?>> searchResults = [];
  bool throwOnUpsert = false;
  bool disposed = false;
  int ensureCount = 0;
  String? searchQuery;
  int? searchTop;
  bool Function(Map<String, Object?> record)? capturedFilter;

  @override
  Future<void> ensureCollectionExists({
    CancellationToken? cancellationToken,
  }) async {
    ensureCount++;
  }

  @override
  Future<void> upsert(
    Iterable<Map<String, Object?>> records, {
    CancellationToken? cancellationToken,
  }) async {
    if (throwOnUpsert) {
      throw StateError('Upsert failed');
    }
    upserted.addAll(records.map(Map<String, Object?>.of));
  }

  @override
  Stream<VectorSearchResult<Map<String, Object?>>> search(
    String queryText,
    int top, {
    VectorSearchOptions<Map<String, Object?>>? options,
    CancellationToken? cancellationToken,
  }) async* {
    searchQuery = queryText;
    searchTop = top;
    capturedFilter = options?.filter;

    final filtered = searchResults
        .where((record) => options?.filter?.call(record) ?? true)
        .take(top);
    for (final record in filtered) {
      yield VectorSearchResult(record, 1.0);
    }
  }

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
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
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
