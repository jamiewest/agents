import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';
import 'package:pool/pool.dart';

import '../../abstractions/agent_session.dart';
import '../../abstractions/ai_context.dart';
import '../../abstractions/ai_context_provider.dart';
import '../../abstractions/message_ai_context_provider.dart';
import '../../abstractions/provider_session_state_t_state_.dart';
import '../agent_json_utilities.dart';
import 'chat_history_memory_provider_options.dart';
import 'chat_history_memory_provider_scope.dart';

/// A vector store that can create dynamic collections for chat-history memory.
abstract class VectorStore {
  VectorStoreCollection<Object, Map<String, Object?>> getDynamicCollection(
    String collectionName,
    VectorStoreCollectionDefinition definition,
  );
}

/// A vector store collection used by [ChatHistoryMemoryProvider].
abstract class VectorStoreCollection<TKey, TRecord> implements Disposable {
  Future<void> ensureCollectionExists({CancellationToken? cancellationToken});

  Future<void> upsert(
    Iterable<TRecord> records, {
    CancellationToken? cancellationToken,
  });

  Stream<VectorSearchResult<TRecord>> search(
    String queryText,
    int top, {
    VectorSearchOptions<TRecord>? options,
    CancellationToken? cancellationToken,
  });
}

/// Describes the schema of a [VectorStoreCollection] to be created
/// dynamically at runtime.
class VectorStoreCollectionDefinition {
  VectorStoreCollectionDefinition({List<VectorStoreProperty>? properties})
    : properties = properties ?? [];

  final List<VectorStoreProperty> properties;
}

/// Describes a single property (field) within a [VectorStoreCollectionDefinition].
class VectorStoreProperty {
  VectorStoreProperty(
    this.name,
    this.type, {
    this.isIndexed = false,
    this.isFullTextIndexed = false,
    this.dimensions,
  });

  final String name;
  final Type type;
  final bool isIndexed;
  final bool isFullTextIndexed;
  final int? dimensions;
}

/// Options that control a vector store search query.
class VectorSearchOptions<TRecord> {
  VectorSearchOptions({this.filter});

  final bool Function(TRecord record)? filter;
}

/// A single result returned by a vector store search operation.
class VectorSearchResult<TRecord> {
  VectorSearchResult(this.record, [this.score]);

  final TRecord record;
  final double? score;
}

/// A context provider that stores all chat history in a vector store and is
/// able to retrieve related chat history later to augment the conversation.
class ChatHistoryMemoryProvider extends MessageAIContextProvider
    implements Disposable {
  ChatHistoryMemoryProvider(
    VectorStore? vectorStore,
    String? collectionName,
    int vectorDimensions,
    State Function(AgentSession?)? stateInitializer, {
    ChatHistoryMemoryProviderOptions? options,
    LoggerFactory? loggerFactory,
  }) : _collection = _validateVectorStore(vectorStore).getDynamicCollection(
         _validateCollectionName(collectionName),
         _createCollectionDefinition(vectorDimensions),
       ),
       super(
         provideInputMessageFilter: options?.searchInputMessageFilter,
         storeInputRequestMessageFilter:
             options?.storageInputRequestMessageFilter,
         storeInputResponseMessageFilter:
             options?.storageInputResponseMessageFilter,
       ) {
    if (stateInitializer == null) {
      throw ArgumentError.notNull('stateInitializer');
    }

    final resolvedOptions = options ?? ChatHistoryMemoryProviderOptions();
    _sessionState = ProviderSessionState<State>(
      stateInitializer,
      resolvedOptions.stateKey ?? runtimeType.toString(),
      JsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );

    final maxResults = resolvedOptions.maxResults;
    if (maxResults != null && maxResults <= 0) {
      throw ArgumentError.value(
        maxResults,
        'maxResults',
        'Maximum results must be greater than zero.',
      );
    }

    _maxResults = maxResults ?? defaultMaxResults;
    _contextPrompt = resolvedOptions.contextPrompt ?? defaultContextPrompt;
    _redactor = resolvedOptions.enableSensitiveTelemetryData
        ? NullRedactor.instance
        : (resolvedOptions.redactor ?? replacingRedactor('<redacted>'));
    _searchTime = resolvedOptions.searchTime;
    _logger = loggerFactory?.createLogger('ChatHistoryMemoryProvider');
    _toolName = resolvedOptions.functionToolName ?? defaultFunctionToolName;
    _toolDescription =
        resolvedOptions.functionToolDescription ??
        defaultFunctionToolDescription;
  }

  static const String defaultContextPrompt =
      '## Memories\nConsider the following memories when answering user questions:';
  static const int defaultMaxResults = 3;
  static const String defaultFunctionToolName = 'Search';
  static const String defaultFunctionToolDescription =
      'Allows searching for related previous chat history to help answer the user question.';

  static const String keyField = 'Key';
  static const String roleField = 'Role';
  static const String messageIdField = 'MessageId';
  static const String authorNameField = 'AuthorName';
  static const String applicationIdField = 'ApplicationId';
  static const String agentIdField = 'AgentId';
  static const String userIdField = 'UserId';
  static const String sessionIdField = 'SessionId';
  static const String contentField = 'Content';
  static const String createdAtField = 'CreatedAt';
  static const String contentEmbeddingField = 'ContentEmbedding';

  late final ProviderSessionState<State> _sessionState;
  List<String>? _stateKeys;

  final VectorStoreCollection<Object, Map<String, Object?>> _collection;
  late final int _maxResults;
  late final String _contextPrompt;
  late final Redactor _redactor;
  late final SearchBehavior _searchTime;
  late final String _toolName;
  late final String _toolDescription;
  late final Logger? _logger;

  bool _collectionInitialized = false;
  final Pool _initializationPool = Pool(1);
  bool _disposedValue = false;

  @override
  List<String> get stateKeys => _stateKeys ??= [_sessionState.stateKey];

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final state = _sessionState.getOrInitializeState(context.session);
    final searchScope = state.searchScope;

    if (_searchTime == SearchBehavior.onDemandFunctionCalling) {
      final tool = AIFunctionFactory.create(
        name: _toolName,
        description: _toolDescription,
        parametersSchema: const {
          'type': 'object',
          'properties': {
            'userQuestion': {
              'type': 'string',
              'description': 'The user question or search query.',
            },
          },
          'required': ['userQuestion'],
        },
        callback: (arguments, {cancellationToken}) {
          final userQuestion =
              (arguments['userQuestion'] ??
                      arguments['query'] ??
                      arguments['input'] ??
                      '')
                  .toString();
          return searchText(
            userQuestion,
            searchScope,
            cancellationToken: cancellationToken,
          );
        },
      );

      return AIContext()..tools = [tool];
    }

    final messages = await provideMessages(
      MessageInvokingContext(
        context.agent,
        context.session,
        context.aiContext.messages ?? const <ChatMessage>[],
      ),
      cancellationToken: cancellationToken,
    );
    return AIContext()..messages = messages;
  }

  @override
  Future<Iterable<ChatMessage>> invokingMessages(
    MessageInvokingContext context, {
    CancellationToken? cancellationToken,
  }) {
    if (_searchTime != SearchBehavior.beforeAIInvoke) {
      throw StateError(
        'Using the ChatHistoryMemoryProvider as a MessageAIContextProvider is not supported when searchTime is set to ${SearchBehavior.onDemandFunctionCalling}.',
      );
    }

    return super.invokingMessages(
      context,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<Iterable<ChatMessage>> provideMessages(
    MessageInvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final state = _sessionState.getOrInitializeState(context.session);
    final searchScope = state.searchScope;

    try {
      final requestText = context.requestMessages
          .where((message) => message.text.trim().isNotEmpty)
          .map((message) => message.text)
          .join('\n');

      if (requestText.trim().isEmpty) {
        return const <ChatMessage>[];
      }

      final contextText = await searchText(
        requestText,
        searchScope,
        cancellationToken: cancellationToken,
      );

      if (contextText.trim().isEmpty) {
        return const <ChatMessage>[];
      }

      return [ChatMessage.fromText(ChatRole.user, contextText)];
    } catch (error) {
      if (_logger?.isEnabled(LogLevel.error) == true) {
        _logger!.logError(
          "ChatHistoryMemoryProvider: Failed to search for chat history due to error. ApplicationId: '${searchScope.applicationId}', AgentId: '${searchScope.agentId}', SessionId: '${searchScope.sessionId}', UserId: '${sanitizeLogData(searchScope.userId)}'.",
          error: error,
        );
      }

      return const <ChatMessage>[];
    }
  }

  @override
  Future<void> storeAIContext(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final state = _sessionState.getOrInitializeState(context.session);
    final storageScope = state.storageScope;

    try {
      final collection = await ensureCollectionExists(
        cancellationToken: cancellationToken,
      );
      final itemsToStore =
          [...context.requestMessages, ...?context.responseMessages].map((
            message,
          ) {
            final text = message.text;
            return <String, Object?>{
              keyField: _newKey(),
              roleField: message.role.toString(),
              messageIdField: message.messageId,
              authorNameField: message.authorName,
              applicationIdField: storageScope.applicationId,
              agentIdField: storageScope.agentId,
              userIdField: storageScope.userId,
              sessionIdField: storageScope.sessionId,
              contentField: text,
              createdAtField:
                  message.createdAt?.toUtc().toIso8601String() ??
                  clock.now().toUtc().toIso8601String(),
              contentEmbeddingField: text,
            };
          }).toList();

      if (itemsToStore.isNotEmpty) {
        await collection.upsert(
          itemsToStore,
          cancellationToken: cancellationToken,
        );
      }
    } catch (error) {
      if (_logger?.isEnabled(LogLevel.error) == true) {
        _logger!.logError(
          "ChatHistoryMemoryProvider: Failed to add messages to chat history vector store due to error. ApplicationId: '${storageScope.applicationId}', AgentId: '${storageScope.agentId}', SessionId: '${storageScope.sessionId}', UserId: '${sanitizeLogData(storageScope.userId)}'.",
          error: error,
        );
      }
    }
  }

  Future<String> searchText(
    String userQuestion,
    ChatHistoryMemoryProviderScope searchScope, {
    CancellationToken? cancellationToken,
  }) async {
    if (userQuestion.trim().isEmpty) {
      return '';
    }

    final results = await searchChatHistory(
      userQuestion,
      searchScope,
      _maxResults,
      cancellationToken: cancellationToken,
    );
    if (results.isEmpty) {
      return '';
    }

    final outputResultsText = results
        .map((result) => result[contentField] as String?)
        .where((content) => content != null && content.trim().isNotEmpty)
        .join('\n');

    if (outputResultsText.trim().isEmpty) {
      return '';
    }

    final formatted = '$_contextPrompt\n$outputResultsText';
    if (_logger?.isEnabled(LogLevel.trace) == true) {
      _logger!.logTrace(
        "ChatHistoryMemoryProvider: Search Results\nInput:${sanitizeLogData(userQuestion)}\nOutput:${sanitizeLogData(formatted)}\n ApplicationId: '${searchScope.applicationId}', AgentId: '${searchScope.agentId}', SessionId: '${searchScope.sessionId}', UserId: '${sanitizeLogData(searchScope.userId)}'.",
      );
    }

    return formatted;
  }

  Future<List<Map<String, Object?>>> searchChatHistory(
    String queryText,
    ChatHistoryMemoryProviderScope searchScope,
    int top, {
    CancellationToken? cancellationToken,
  }) async {
    if (queryText.trim().isEmpty) {
      return <Map<String, Object?>>[];
    }

    final collection = await ensureCollectionExists(
      cancellationToken: cancellationToken,
    );
    final filter = _createScopeFilter(searchScope);
    final searchResults = collection.search(
      queryText,
      top,
      options: VectorSearchOptions<Map<String, Object?>>(filter: filter),
      cancellationToken: cancellationToken,
    );

    final results = <Map<String, Object?>>[];
    await for (final result in searchResults) {
      results.add(result.record);
    }

    if (_logger?.isEnabled(LogLevel.information) == true) {
      _logger!.logInformation(
        "ChatHistoryMemoryProvider: Retrieved ${results.length} search results. ApplicationId: '${searchScope.applicationId}', AgentId: '${searchScope.agentId}', SessionId: '${searchScope.sessionId}', UserId: '${sanitizeLogData(searchScope.userId)}'.",
      );
    }

    return results;
  }

  Future<VectorStoreCollection<Object, Map<String, Object?>>>
  ensureCollectionExists({CancellationToken? cancellationToken}) async {
    if (_disposedValue) {
      throw StateError('ChatHistoryMemoryProvider disposed');
    }

    if (_collectionInitialized) {
      return _collection;
    }

    return _initializationPool.withResource(() async {
      if (_collectionInitialized) {
        return _collection;
      }

      await _collection.ensureCollectionExists(
        cancellationToken: cancellationToken,
      );
      _collectionInitialized = true;
      return _collection;
    });
  }

  @override
  void dispose() {
    if (_disposedValue) {
      return;
    }

    unawaited(_initializationPool.close());
    _collection.dispose();
    _disposedValue = true;
  }

  String sanitizeLogData(String? data) => _redactor.redact(data);

  bool Function(Map<String, Object?> record)? _createScopeFilter(
    ChatHistoryMemoryProviderScope scope,
  ) {
    final filters = <bool Function(Map<String, Object?> record)>[];
    if (scope.applicationId != null) {
      filters.add(
        (record) => record[applicationIdField] == scope.applicationId,
      );
    }
    if (scope.agentId != null) {
      filters.add((record) => record[agentIdField] == scope.agentId);
    }
    if (scope.userId != null) {
      filters.add((record) => record[userIdField] == scope.userId);
    }
    if (scope.sessionId != null) {
      filters.add((record) => record[sessionIdField] == scope.sessionId);
    }

    if (filters.isEmpty) {
      return null;
    }

    return (record) => filters.every((filter) => filter(record));
  }

  static VectorStore _validateVectorStore(VectorStore? vectorStore) {
    if (vectorStore == null) {
      throw ArgumentError.notNull('vectorStore');
    }
    return vectorStore;
  }

  static String _validateCollectionName(String? collectionName) {
    if (collectionName == null) {
      throw ArgumentError.notNull('collectionName');
    }
    if (collectionName.trim().isEmpty) {
      throw ArgumentError.value(
        collectionName,
        'collectionName',
        'Collection name cannot be empty.',
      );
    }
    return collectionName;
  }

  static VectorStoreCollectionDefinition _createCollectionDefinition(
    int vectorDimensions,
  ) {
    if (vectorDimensions < 1) {
      throw ArgumentError.value(
        vectorDimensions,
        'vectorDimensions',
        'Vector dimensions must be greater than zero.',
      );
    }

    return VectorStoreCollectionDefinition(
      properties: [
        VectorStoreProperty(keyField, String),
        VectorStoreProperty(roleField, String, isIndexed: true),
        VectorStoreProperty(messageIdField, String, isIndexed: true),
        VectorStoreProperty(authorNameField, String),
        VectorStoreProperty(applicationIdField, String, isIndexed: true),
        VectorStoreProperty(agentIdField, String, isIndexed: true),
        VectorStoreProperty(userIdField, String, isIndexed: true),
        VectorStoreProperty(sessionIdField, String, isIndexed: true),
        VectorStoreProperty(contentField, String, isFullTextIndexed: true),
        VectorStoreProperty(createdAtField, String, isIndexed: true),
        VectorStoreProperty(
          contentEmbeddingField,
          String,
          dimensions: vectorDimensions,
        ),
      ],
    );
  }

  static String _newKey() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }
}

/// Represents the state of a [ChatHistoryMemoryProvider] stored in the
/// session state bag.
class State {
  State(this.storageScope, {ChatHistoryMemoryProviderScope? searchScope})
    : searchScope = searchScope ?? storageScope;

  final ChatHistoryMemoryProviderScope storageScope;
  final ChatHistoryMemoryProviderScope searchScope;
}
