import 'dart:math';
import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import '../../../func_typedefs.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/message_ai_context_provider.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';
// TODO: import not yet ported
// TODO: import not yet ported
import '../agent_json_utilities.dart';
import 'chat_history_memory_provider_options.dart';
import 'chat_history_memory_provider_scope.dart';
import '../../../semaphore_slim.dart';

/// A context provider that stores all chat history in a vector store and is
/// able to retrieve related chat history later to augment the current
/// conversation.
///
/// Remarks: This provider stores chat messages in a vector store and
/// retrieves relevant previous messages to provide as context during agent
/// invocations. It uses the VectorStore and VectorStoreCollection
/// abstractions to work with any compatible vector store implementation.
/// Messages are stored during the [CancellationToken)] method and retrieved
/// during the [CancellationToken)] method using semantic similarity search.
/// Behavior is configurable through [ChatHistoryMemoryProviderOptions]. When
/// [OnDemandFunctionCalling] is selected the provider exposes a function tool
/// that the model can invoke to retrieve relevant memories on demand instead
/// of injecting them automatically on each invocation. Security
/// considerations: Indirect prompt injection: Messages retrieved from the
/// vector store via semantic search are injected into the LLM context. If the
/// vector store is compromised, adversarial content could influence LLM
/// behavior. The data returned from the store is accepted as-is without
/// validation or sanitization. PII and sensitive data: Conversation messages
/// (including user inputs and LLM responses) are stored as vectors in the
/// underlying store. These messages may contain PII or sensitive information.
/// Ensure the vector store is configured with appropriate access controls and
/// encryption at rest. On-demand search tool: When using
/// [OnDemandFunctionCalling], the AI model controls when and what to search
/// for. The search query is AI-generated and should be treated as untrusted
/// input by the vector store implementation. Trace logging: When [Trace] is
/// enabled, full search queries and results may be logged. This data may
/// contain PII.
class ChatHistoryMemoryProvider extends MessageAIContextProvider implements Disposable {
  /// Initializes a new instance of the [ChatHistoryMemoryProvider] class.
  ///
  /// [vectorStore] The vector store to use for storing and retrieving chat
  /// history.
  ///
  /// [collectionName] The name of the collection for storing chat history in
  /// the vector store.
  ///
  /// [vectorDimensions] The number of dimensions to use for the chat history
  /// vector store embeddings.
  ///
  /// [stateInitializer] A delegate that initializes the provider state on the
  /// first invocation, providing the storage and search scopes.
  ///
  /// [options] Optional configuration options.
  ///
  /// [loggerFactory] Optional logger factory.
  ChatHistoryMemoryProvider(
    VectorStore vectorStore,
    String collectionName,
    int vectorDimensions,
    Func<AgentSession?, State> stateInitializer,
    {ChatHistoryMemoryProviderOptions? options = null, LoggerFactory? loggerFactory = null, },
  ) : _vectorStore = vectorStore {
    this._sessionState = ProviderSessionState<State>(
            stateInitializer,
            options?.stateKey ?? this.runtimeType.toString(),
            AgentJsonUtilities.defaultOptions);
    options ??= chatHistoryMemoryProviderOptions();
    this._maxResults = options.maxResults.hasValue ? Throw.ifLessThanOrEqual(
      options.maxResults.value,
      0,
    ) : DefaultMaxResults;
    this._contextPrompt = options.contextPrompt ?? DefaultContextPrompt;
    this._redactor = options.enableSensitiveTelemetryData ? NullRedactor.instance : (options.redactor ?? replacingRedactor("<redacted>"));
    this._searchTime = options.searchTime;
    this._logger = loggerFactory?.createLogger<ChatHistoryMemoryProvider>();
    this._toolName = options.functionToolName ?? DefaultFunctionToolName;
    this._toolDescription = options.functionToolDescription ?? DefaultFunctionToolDescription;
    var definition = vectorStoreCollectionDefinition(),
                vectorStoreDataProperty(MessageIdField, String) { IsIndexed = true },
                vectorStoreDataProperty(AuthorNameField, String),
                vectorStoreDataProperty(ApplicationIdField, String) { IsIndexed = true },
                vectorStoreDataProperty(AgentIdField, String) { IsIndexed = true },
                vectorStoreDataProperty(UserIdField, String) { IsIndexed = true },
                vectorStoreDataProperty(SessionIdField, String) { IsIndexed = true },
                vectorStoreDataProperty(ContentField, String) { IsFullTextIndexed = true },
                vectorStoreDataProperty(CreatedAtField, String) { IsIndexed = true },
                vectorStoreVectorProperty(
                  ContentEmbeddingField,
                  String,
                  vectorDimensions,
                )
            ]
        };
  this._collection = this._vectorStore.getDynamicCollection(
    collectionName,
    definition,
  );
}

late final ProviderSessionState<State> _sessionState;

List<String>? _stateKeys;

final VectorStore _vectorStore;

final VectorStoreCollection<Object, Map<String, Object?>> _collection;

late final int _maxResults;

late final String _contextPrompt;

late final Redactor _redactor;

late final SearchBehavior _searchTime;

late final String _toolName;

late final String _toolDescription;

late final Logger<ChatHistoryMemoryProvider>? _logger;

late bool _collectionInitialized;

final SemaphoreSlim _initializationLock = SemaphoreSlim(1, 1);

late bool _disposedValue;

List<String> get stateKeys {
return this._stateKeys ??= [this._sessionState.stateKey];
 }
@override
Future<AIContext> provideAIContext(
  InvokingContext context,
  {CancellationToken? cancellationToken, },
) async  {
var state = this._sessionState.getOrInitializeState(context.session);
var searchScope = state.searchScope;
if (this._searchTime == ChatHistoryMemoryProviderOptions.searchBehavior.onDemandFunctionCalling) {
  /* TODO: unsupported node kind "unknown" */
// Task<String> InlineSearchAsync(String userQuestion, CancellationToken ct)
//                 => this.SearchTextAsync(userQuestion, searchScope, ct);
  var tools = [
                AIFunctionFactory.create(
                    InlineSearchAsync,
                    name: this._toolName,
                    description: this._toolDescription)
            ];
  return AIContext();
}
return AIContext();
 }
@override
Future<Iterable<ChatMessage>> invokingCore(
  InvokingContext context,
  {CancellationToken? cancellationToken, },
) {
if (this._searchTime != ChatHistoryMemoryProviderOptions.searchBehavior.beforeAIInvoke) {
  throw StateError('Using the ${'ChatHistoryMemoryProvider'} as a ${'MessageAIContextProvider'} is! supported when ${'searchTime'} is set to ${ChatHistoryMemoryProviderOptions.searchBehavior.onDemandFunctionCalling}.');
}
return super.invokingCore(context, cancellationToken);
 }
@override
Future<Iterable<ChatMessage>> provideMessages(
  InvokingContext context,
  {CancellationToken? cancellationToken, },
) async  {
var state = this._sessionState.getOrInitializeState(context.session);
var searchScope = state.searchScope;
try {
  var requestText = (context.requestMessages ?? [].join("\n")
                .where((m) => m != null && !(m.text == null || m.text.trim().isEmpty))
                .map((m) => m.text));
  if ((requestText == null || requestText.trim().isEmpty)) {
    return [];
  }

  var contextText = await this.searchTextAsync(
    requestText,
    searchScope,
    cancellationToken,
  ) ;
  if ((contextText == null || contextText.trim().isEmpty)) {
    return [];
  }

  return [ChatMessage.fromText(ChatRole.user, contextText)];
} catch (e, s) {
  if (e is Exception) {
    final ex = e as Exception;
    {
    if (this._logger?.isEnabled(LogLevel.error) is true) {
      this._logger.logError(
                    ex,
                    "ChatHistoryMemoryProvider: Failed to search for chat history due to error. ApplicationId: '{ApplicationId}', AgentId: '{AgentId}', SessionId: '{SessionId}', UserId: '{UserId}'.",
                    searchScope.applicationId,
                    searchScope.agentId,
                    searchScope.sessionId,
                    this.sanitizeLogData(searchScope.userId));
    }
    return [];
  }

  } else {
    rethrow;
}
}
 }
@override
Future storeAIContext(InvokedContext context, {CancellationToken? cancellationToken, }) async  {
var state = this._sessionState.getOrInitializeState(context.session);
var storageScope = state.storageScope;
try {
  var collection = await this.ensureCollectionExists(cancellationToken);
  var itemsToStore = context.requestMessages
                 + context.responseMessages ?? []
                .map((message) => <Map entry>{
                    [KeyField] = List.generate(32, (_) => Random.secure().nextInt(16).toRadixString(16)).join(),
                    [RoleField] = message.role.toString(),
                    [MessageIdField] = message.messageId,
                    [AuthorNameField] = message.authorName,
                    [ApplicationIdField] = storageScope.applicationId,
                    [AgentIdField] = storageScope.agentId,
                    [UserIdField] = storageScope.userId,
                    [SessionIdField] = storageScope.sessionId,
                    [ContentField] = message.text,
                    [CreatedAtField] = message.createdAt?.toString("O") ?? DateTime.now().toUtc().toString("O"),
                    [ContentEmbeddingField] = message.text,
                })
                .toList();
  if (itemsToStore.length > 0) {
    await collection.upsert(itemsToStore, cancellationToken);
  }

} catch (e, s) {
  if (e is Exception) {
    final ex = e as Exception;
    {
    if (this._logger?.isEnabled(LogLevel.error) is true) {
      this._logger.logError(
                    ex,
                    "ChatHistoryMemoryProvider: Failed to add messages to chat history vector store due to error. ApplicationId: '{ApplicationId}', AgentId: '{AgentId}', SessionId: '{SessionId}', UserId: '{UserId}'.",
                    storageScope.applicationId,
                    storageScope.agentId,
                    storageScope.sessionId,
                    this.sanitizeLogData(storageScope.userId));
    }
  }

  } else {
    rethrow;
}
}
 }
/// Function callable by the AI model (when enabled) to perform an ad-hoc chat
/// history search.
///
/// Returns: Formatted search results (may be empty).
///
/// [userQuestion] The query text.
///
/// [searchScope] The scope to filter search results with.
///
/// [cancellationToken] Cancellation token.
Future<String> searchText(
  String userQuestion,
  ChatHistoryMemoryProviderScope searchScope,
  {CancellationToken? cancellationToken, },
) async  {
if ((userQuestion == null || userQuestion.trim().isEmpty)) {
  return '';
}
var results = await this.searchChatHistoryAsync(
  userQuestion,
  searchScope,
  this._maxResults,
  cancellationToken,
) ;
if (!results.isNotEmpty) {
  return '';
}
var outputResultsText = String.join(
  "\n",
  results.map((x) => (String?)x[ContentField]).where((c) => !(c == null || c.trim().isEmpty)),
);
if ((outputResultsText == null || outputResultsText.trim().isEmpty)) {
  return '';
}
var formatted = '${this._contextPrompt}\n${outputResultsText}';
if (this._logger?.isEnabled(LogLevel.trace) is true) {
  this._logger.logTrace(
                "ChatHistoryMemoryProvider: Search Results\nInput:{Input}\nOutput:{MessageText}\n ApplicationId: '{ApplicationId}', AgentId: '{AgentId}', SessionId: '{SessionId}', UserId: '{UserId}'.",
                this.sanitizeLogData(userQuestion),
                this.sanitizeLogData(formatted),
                searchScope.applicationId,
                searchScope.agentId,
                searchScope.sessionId,
                this.sanitizeLogData(searchScope.userId));
}
return formatted;
 }
/// Searches for relevant chat history items based on the provided query text.
///
/// Returns: A list of relevant chat history items.
///
/// [queryText] The text to search for.
///
/// [searchScope] The scope to filter search results with.
///
/// [top] The maximum number of results to return.
///
/// [cancellationToken] The cancellation token.
Future<Iterable<Map<String, Object?>>> searchChatHistory(
  String queryText,
  ChatHistoryMemoryProviderScope searchScope,
  int top,
  {CancellationToken? cancellationToken, },
) async  {
if ((queryText == null || queryText.trim().isEmpty)) {
  return [];
}
var collection = await this.ensureCollectionExists(cancellationToken);
var applicationId = searchScope.applicationId;
var agentId = searchScope.agentId;
var userId = searchScope.userId;
var sessionId = searchScope.sessionId;
var parameter = Expression.parameter(Dictionary<String, Object?>, "x");
var filterBody = null;
if (applicationId != null) {
  filterBody = rebindFilterBody((x) => (String?)x[ApplicationIdField] == applicationId, parameter);
}
if (agentId != null) {
  var body = rebindFilterBody((x) => (String?)x[AgentIdField] == agentId, parameter);
  filterBody = filterBody == null ? body : Expression.andAlso(filterBody, body);
}
if (userId != null) {
  var body = rebindFilterBody((x) => (String?)x[UserIdField] == userId, parameter);
  filterBody = filterBody == null ? body : Expression.andAlso(filterBody, body);
}
if (sessionId != null) {
  var body = rebindFilterBody((x) => (String?)x[SessionIdField] == sessionId, parameter);
  filterBody = filterBody == null ? body : Expression.andAlso(filterBody, body);
}
var filter = filterBody != null
            ? Expression.lambda<Func<Dictionary<String, Object?>, bool>>(filterBody, parameter)
            : null;
var searchResults = collection.search(
            queryText,
            top,
            options: new()
            {
                Filter = filter
            },
            cancellationToken: cancellationToken);
var results = new List<Map<String, Object?>>();
for (final result in searchResults.withCancellation(cancellationToken)) {
  results.add(result.record);
}
if (this._logger?.isEnabled(LogLevel.information) is true) {
  this._logger.logInformation(
                "ChatHistoryMemoryProvider: Retrieved {Count} search results. ApplicationId: '{ApplicationId}', AgentId: '{AgentId}', SessionId: '{SessionId}', UserId: '{UserId}'.",
                results.length,
                searchScope.applicationId,
                searchScope.agentId,
                searchScope.sessionId,
                this.sanitizeLogData(searchScope.userId));
}
return results;
 }
/// Ensures the collection exists in the vector store, creating it if
/// necessary.
///
/// Returns: The vector store collection.
///
/// [cancellationToken] The cancellation token.
Future<VectorStoreCollection<Object, Map<String, Object?>>> ensureCollectionExists({CancellationToken? cancellationToken}) async  {
if (this._collectionInitialized) {
  return this._collection;
}
await this._initializationLock.waitAsync(cancellationToken);
try {
  if (this._collectionInitialized) {
    return this._collection;
  }

  await this._collection.ensureCollectionExists(cancellationToken);
  this._collectionInitialized = true;
  return this._collection;
} finally {
  this._initializationLock.release();
}
 }
@override
void dispose({bool? disposing}) {
if (!this._disposedValue) {
  if (disposing) {
    this._initializationLock.dispose();
    this._collection?.dispose();
  }

  this._disposedValue = true;
}
 }
String sanitizeLogData(String? data) {
return this._redactor.redact(data);
 }
/// Rebinds a filter expression's body to use the specified shared parameter,
/// replacing the original lambda parameter so that multiple filters can be
/// safely combined with [Expression)].
static Expression rebindFilterBody(
  Expression<Func<Map<String, Object?>, bool>> filter,
  ParameterExpression sharedParameter,
) {
return parameterReplacer(filter.parameters[0], sharedParameter).visit(filter.body);
 }
 }
/// An [ExpressionVisitor] that replaces one [ParameterExpression] with
/// another.
class ParameterReplacer extends ExpressionVisitor {
  /// An [ExpressionVisitor] that replaces one [ParameterExpression] with
  /// another.
  const ParameterReplacer(ParameterExpression original, ParameterExpression replacement, );

  @override
  Expression visitParameter(ParameterExpression node) {
    return node == original ? replacement : super.visitParameter(node);
  }
}
/// Represents the state of a [ChatHistoryMemoryProvider] stored in the
/// [StateBag].
class State {
  /// Initializes a new instance of the [State] class with the specified storage
  /// and search scopes.
  ///
  /// [storageScope] The scope to use when storing chat history messages.
  ///
  /// [searchScope] The scope to use when searching for relevant chat history
  /// messages. If null, the storage scope will be used for searching as well.
  State(
    ChatHistoryMemoryProviderScope storageScope,
    {ChatHistoryMemoryProviderScope? searchScope = null, },
  ) : storageScope = storageScope {
    this.searchScope = searchScope ?? storageScope;
  }

  /// Gets or sets the scope used when storing chat history messages.
  final ChatHistoryMemoryProviderScope storageScope;

  /// Gets or sets the scope used when searching chat history messages.
  late final ChatHistoryMemoryProviderScope searchScope;

}
