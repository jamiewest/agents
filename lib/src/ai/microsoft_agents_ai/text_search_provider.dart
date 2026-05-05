import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import '../../func_typedefs.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/message_ai_context_provider.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';
// TODO: import not yet ported
import 'agent_json_utilities.dart';
import 'text_search_provider_options.dart';

/// A text search context provider that performs a search over external
/// knowledge and injects the formatted results into the AI invocation
/// context, or exposes a search tool for on-demand use. This provider can be
/// used to enable Retrieval Augmented Generation (RAG) on an agent.
///
/// Remarks: The provider supports two behaviors controlled via [SearchTime]:
/// [BeforeAIInvoke] – Automatically performs a search prior to every AI
/// invocation and injects results as additional messages.
/// [OnDemandFunctionCalling] – Exposes a function tool that the model may
/// invoke to retrieve contextual information when needed. When
/// [RecentMessageMemoryLimit] is greater than zero the provider will retain
/// the most recent user and assistant messages (up to the configured limit)
/// across invocations and prepend them (in chronological order) to the
/// current request messages when forming the search input. This can improve
/// search relevance by providing multi-turn context to the retrieval layer
/// without permanently altering the conversation history. Security
/// considerations: Search results retrieved from external sources are
/// injected into the LLM context and may contain adversarial content designed
/// to manipulate LLM behavior via indirect prompt injection. Developers
/// should be aware that: The search query may be constructed from user input
/// or LLM-generated content, both of which are untrusted. Implementers of the
/// search delegate should validate search inputs and apply appropriate access
/// controls to search results. Retrieved documents are formatted and injected
/// as messages in the AI request context. If the external data source is
/// compromised, adversarial content could influence the LLM's responses. When
/// using [OnDemandFunctionCalling], the AI model controls when and what to
/// search for — the search query text is AI-generated and should be treated
/// as untrusted input by the search implementation.
class TextSearchProvider extends MessageAIContextProvider {
  /// Initializes a new instance of the [TextSearchProvider] class.
  ///
  /// [searchAsync] Delegate that executes the search logic. Must not be `null`.
  ///
  /// [options] Optional configuration options.
  ///
  /// [loggerFactory] Optional logger factory.
  TextSearchProvider(
    Func2<String, CancellationToken, Future<Iterable<TextSearchResult>>> searchAsync,
    {TextSearchProviderOptions? options = null, LoggerFactory? loggerFactory = null, },
  ) : _searchAsync = searchAsync {
    this._sessionState = ProviderSessionState<TextSearchProviderState>(
            (_) => textSearchProviderState(),
            options?.stateKey ?? this.runtimeType.toString(),
            AgentJsonUtilities.defaultOptions);
    // Validate and assign parameters
    this._logger = loggerFactory?.createLogger<TextSearchProvider>();
    this._recentMessageMemoryLimit = options?.recentMessageMemoryLimit ?? 0;
    this._recentMessageRolesIncluded = options?.recentMessageRolesIncluded ?? [ChatRole.user];
    this._searchTime = options?.searchTime ?? TextSearchProviderOptions.textSearchBehavior.beforeAIInvoke;
    this._contextPrompt = options?.contextPrompt ?? DefaultContextPrompt;
    this._citationsPrompt = options?.citationsPrompt ?? DefaultCitationsPrompt;
    this._contextFormatter = options?.contextFormatter;
    this._redactor = options?.enableSensitiveTelemetryData == true ? NullRedactor.instance : (options?.redactor ?? replacingRedactor("<redacted>"));
    // Create the on-demand search tool (only used if behavior is OnDemandFunctionCalling)
        this._tools =
        [
            AIFunctionFactory.create(
                this.searchAsync,
                name: options?.functionToolName ?? DefaultPluginSearchFunctionName,
                description: options?.functionToolDescription ?? DefaultPluginSearchFunctionDescription)
        ];
  }

  late final ProviderSessionState<TextSearchProviderState> _sessionState;

  List<String>? _stateKeys;

  final Func2<String, CancellationToken, Future<Iterable<TextSearchResult>>> _searchAsync;

  late final Logger<TextSearchProvider>? _logger;

  late final List<AITool> _tools;

  late final List<ChatRole> _recentMessageRolesIncluded;

  late final int _recentMessageMemoryLimit;

  late final TextSearchBehavior _searchTime;

  late final String _contextPrompt;

  late final String _citationsPrompt;

  final Func<List<TextSearchResult>, String>? _contextFormatter;

  late final Redactor _redactor;

  List<String> get stateKeys {
    return this._stateKeys ??= [this._sessionState.stateKey];
  }

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context,
    {CancellationToken? cancellationToken, },
  ) async  {
    if (this._searchTime != TextSearchProviderOptions.textSearchBehavior.beforeAIInvoke) {
      return AIContext();
    }
    return AIContext();
  }

  @override
  Future<Iterable<ChatMessage>> invokingCore(
    InvokingContext context,
    {CancellationToken? cancellationToken, },
  ) {
    if (this._searchTime != TextSearchProviderOptions.textSearchBehavior.beforeAIInvoke) {
      throw StateError('Using the ${'TextSearchProvider'} as a ${'MessageAIContextProvider'} is! supported when ${'searchTime'} is set to ${TextSearchProviderOptions.textSearchBehavior.onDemandFunctionCalling}.');
    }
    return super.invokingCore(context, cancellationToken);
  }

  @override
  Future<Iterable<ChatMessage>> provideMessages(
    InvokingContext context,
    {CancellationToken? cancellationToken, },
  ) async  {
    var recentMessagesText = this._sessionState.getOrInitializeState(context.session).recentMessagesText
            ?? [];
    var sbInput = StringBuffer();
    var requestMessagesText = (context.requestMessages ?? [])
            .where((x) => !(x?.text == null || x?.text.trim().isEmpty)).map((x) => x.text);
    for (final messageText in recentMessagesText + requestMessagesText) {
      if (sbInput.length > 0) {
        sbInput.write('\n');
      }
      sbInput.write(messageText);
    }
    var input = sbInput.toString();
    try {
      var results = await this._searchAsync(input, cancellationToken);
      var materialized = results as IList<TextSearchResult> ?? results.toList();
      if (this._logger?.isEnabled(LogLevel.information) is true) {
        this._logger?.logInformation(
          "TextSearchProvider: Retrieved {Count} search results.",
          materialized.length,
        );
      }
      if (materialized.length == 0) {
        return [];
      }
      var formatted = this.formatResults(materialized);
      if (this._logger?.isEnabled(LogLevel.trace) is true) {
        this._logger.logTrace(
          "TextSearchProvider: Search Results\nInput:{Input}\nOutput:{MessageText}",
          this.sanitizeLogData(input),
          this.sanitizeLogData(formatted),
        );
      }
      return [ChatMessage.fromText(ChatRole.user, formatted)];
    } catch (e, s) {
      if (e is Exception) {
        final ex = e as Exception;
        {
          this._logger?.logError(ex, "TextSearchProvider: Failed to search for data due to error");
          return [];
        }
      } else {
        rethrow;
      }
    }
  }

  @override
  Future storeAIContext(InvokedContext context, {CancellationToken? cancellationToken, }) {
    var limit = this._recentMessageMemoryLimit;
    if (limit <= 0) {
      return Future.value();
    }
    if (context.session == null) {
      return Future.value();
    }
    var recentMessagesText = this._sessionState.getOrInitializeState(context.session).recentMessagesText
            ?? [];
    var newMessagesText = context.requestMessages
             + context.responseMessages ?? []
            .where((m) =>
                this._recentMessageRolesIncluded.contains(m.role) &&
                !(m.text == null || m.text.trim().isEmpty))
            .map((m) => m.text);
    var allMessages = recentMessagesText + newMessagesText.toList();
    var updatedMessages = allMessages.length > limit
            ? allMessages.skip(allMessages.length - limit).toList()
            : allMessages;
    // Store updated state back to the session.
        this._sessionState.saveState(
            context.session,
            textSearchProviderState());
    return Future.value();
  }

  /// Function callable by the AI model (when enabled) to perform an ad-hoc
  /// search.
  ///
  /// Returns: Formatted search results.
  ///
  /// [userQuestion] The query text.
  ///
  /// [cancellationToken] Cancellation token.
  Future<String> search(String userQuestion, {CancellationToken? cancellationToken, }) async  {
    var results = await this._searchAsync(userQuestion, cancellationToken);
    var materialized = results as IList<TextSearchResult> ?? results.toList();
    var outputText = this.formatResults(materialized);
    if (this._logger?.isEnabled(LogLevel.information) is true) {
      this._logger.logInformation(
        "TextSearchProvider: Retrieved {Count} search results.",
        materialized.length,
      );
      if (this._logger.isEnabled(LogLevel.trace)) {
        this._logger.logTrace(
          "TextSearchProvider Input:{UserQuestion}\nOutput:{MessageText}",
          this.sanitizeLogData(userQuestion),
          this.sanitizeLogData(outputText),
        );
      }
    }
    return outputText;
  }

  /// Formats search results into an output String for model consumption.
  ///
  /// Returns: Formatted String (may be empty).
  ///
  /// [results] The results.
  String formatResults(List<TextSearchResult> results) {
    if (this._contextFormatter != null) {
      return this._contextFormatter(results) ?? '';
    }
    if (results.length == 0) {
      return '';
    }
    var sb = StringBuffer();
    sb.writeln(this._contextPrompt);
    for (var i = 0; i < results.length; i++) {
      var result = results[i];
      if (!(result.sourceName == null || result.sourceName.trim().isEmpty)) {
        sb.writeln('SourceDocName: ${result.sourceName}');
      }
      if (!(result.sourceLink == null || result.sourceLink.trim().isEmpty)) {
        sb.writeln('SourceDocLink: ${result.sourceLink}');
      }
      sb.writeln('Contents: ${result.text}');
      sb.writeln("----");
    }
    sb.writeln(this._citationsPrompt);
    sb.writeln();
    return sb.toString();
  }

  String sanitizeLogData(String? data) {
    return this._redactor.redact(data);
  }
}
/// Represents the per-session state of a [TextSearchProvider] stored in the
/// [StateBag].
class TextSearchProviderState {
  TextSearchProviderState();

  /// Gets or sets the list of recent message texts retained for multi-turn
  /// search context.
  List<String>? recentMessagesText;

}
/// Represents a single retrieved text search result.
class TextSearchResult {
  TextSearchResult();

  /// Gets or sets the display name of the source document (optional).
  String? sourceName;

  /// Gets or sets a link/URL to the source document (optional).
  String? sourceLink;

  /// Gets or sets the textual content of the retrieved chunk.
  String text = '';

  /// Gets or sets the raw representation of the search result from the data
  /// source.
  ///
  /// Remarks: If a [TextSearchResult] is created to represent some underlying
  /// Object from another Object model, this property can be used to store that
  /// original Object. This can be useful for debugging or for enabling the
  /// [ContextFormatter] to access the underlying Object model if needed.
  Object? rawRepresentation;

}
