import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../abstractions/ai_context.dart';
import '../abstractions/ai_context_provider.dart';
import '../abstractions/message_ai_context_provider.dart';
import '../abstractions/provider_session_state_t_state_.dart';
import 'agent_json_utilities.dart';
import 'memory/chat_history_memory_provider_options.dart';
import 'text_search_provider_options.dart';

typedef TextSearchAsync =
    Future<Iterable<TextSearchResult>> Function(
      String input,
      CancellationToken cancellationToken,
    );

/// A text search context provider that performs a search over external
/// knowledge and injects formatted results into the AI invocation context, or
/// exposes a search tool for on-demand use.
class TextSearchProvider extends MessageAIContextProvider {
  TextSearchProvider(
    TextSearchAsync? searchAsync, {
    TextSearchProviderOptions? options,
    LoggerFactory? loggerFactory,
  }) : _searchAsync = _validateSearchAsync(searchAsync),
       super(
         provideInputMessageFilter: options?.searchInputMessageFilter,
         storeInputRequestMessageFilter:
             options?.storageInputRequestMessageFilter,
         storeInputResponseMessageFilter:
             options?.storageInputResponseMessageFilter,
       ) {
    final resolvedOptions = options ?? TextSearchProviderOptions();
    if (resolvedOptions.recentMessageMemoryLimit < 0) {
      throw ArgumentError.value(
        resolvedOptions.recentMessageMemoryLimit,
        'recentMessageMemoryLimit',
        'Recent message memory limit must be greater than or equal to zero.',
      );
    }

    _sessionState = ProviderSessionState<TextSearchProviderState>(
      (_) => TextSearchProviderState(),
      resolvedOptions.stateKey ?? runtimeType.toString(),
      JsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );
    _logger = loggerFactory?.createLogger('TextSearchProvider');
    _recentMessageMemoryLimit = resolvedOptions.recentMessageMemoryLimit;
    _recentMessageRolesIncluded =
        resolvedOptions.recentMessageRolesIncluded ?? [ChatRole.user];
    _searchTime = resolvedOptions.searchTime;
    _contextPrompt = resolvedOptions.contextPrompt ?? defaultContextPrompt;
    _citationsPrompt =
        resolvedOptions.citationsPrompt ?? defaultCitationsPrompt;
    _contextFormatter = resolvedOptions.contextFormatter;
    _redactor = resolvedOptions.enableSensitiveTelemetryData
        ? NullRedactor.instance
        : (resolvedOptions.redactor ?? replacingRedactor('<redacted>'));
    _tools = [
      AIFunctionFactory.create(
        name:
            resolvedOptions.functionToolName ?? defaultPluginSearchFunctionName,
        description:
            resolvedOptions.functionToolDescription ??
            defaultPluginSearchFunctionDescription,
        parametersSchema: const {
          'type': 'object',
          'properties': {
            'userQuestion': {
              'type': 'string',
              'description': 'The question or search query.',
            },
          },
          'required': ['userQuestion'],
        },
        callback: (arguments, {CancellationToken? cancellationToken}) {
          final userQuestion =
              (arguments['userQuestion'] ??
                      arguments['query'] ??
                      arguments['input'] ??
                      '')
                  .toString();
          return search(userQuestion, cancellationToken: cancellationToken);
        },
      ),
    ];
  }

  static const String defaultContextPrompt =
      '## Search results\nUse the following retrieved context to help answer the user.';
  static const String defaultCitationsPrompt =
      'Cite the source document name or link when it is relevant.';
  static const String defaultPluginSearchFunctionName = 'Search';
  static const String defaultPluginSearchFunctionDescription =
      'Allows searching for relevant information to help answer the user question.';

  late final ProviderSessionState<TextSearchProviderState> _sessionState;
  List<String>? _stateKeys;

  final TextSearchAsync _searchAsync;
  late final Logger? _logger;
  late final List<AITool> _tools;
  late final List<ChatRole> _recentMessageRolesIncluded;
  late final int _recentMessageMemoryLimit;
  late final TextSearchBehavior _searchTime;
  late final String _contextPrompt;
  late final String _citationsPrompt;
  late final String Function(List<TextSearchResult>)? _contextFormatter;
  late final Redactor _redactor;

  @override
  List<String> get stateKeys => _stateKeys ??= [_sessionState.stateKey];

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    if (_searchTime == TextSearchBehavior.onDemandFunctionCalling) {
      return AIContext()..tools = _tools;
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
    if (_searchTime != TextSearchBehavior.beforeAIInvoke) {
      throw StateError(
        'Using the TextSearchProvider as a MessageAIContextProvider is not supported when searchTime is set to ${TextSearchBehavior.onDemandFunctionCalling}.',
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
    final input = _buildSearchInput(
      state.recentMessagesText,
      context.requestMessages,
    );
    if (input.trim().isEmpty) {
      return const <ChatMessage>[];
    }

    try {
      final results = await _searchAsync(
        input,
        cancellationToken ?? CancellationToken.none,
      );
      final materialized = results.toList();
      if (_logger?.isEnabled(LogLevel.information) == true) {
        _logger!.logInformation(
          'TextSearchProvider: Retrieved ${materialized.length} search results.',
        );
      }
      if (materialized.isEmpty) {
        return const <ChatMessage>[];
      }

      final formatted = formatResults(materialized);
      if (formatted.trim().isEmpty) {
        return const <ChatMessage>[];
      }

      if (_logger?.isEnabled(LogLevel.trace) == true) {
        _logger!.logTrace(
          'TextSearchProvider: Search Results\nInput:${sanitizeLogData(input)}\nOutput:${sanitizeLogData(formatted)}',
        );
      }
      return [ChatMessage.fromText(ChatRole.user, formatted)];
    } catch (error) {
      _logger?.logError(
        'TextSearchProvider: Failed to search for data due to error.',
        error: error,
      );
      return const <ChatMessage>[];
    }
  }

  @override
  Future<void> storeAIContext(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final limit = _recentMessageMemoryLimit;
    if (limit <= 0 || context.session == null) {
      return;
    }

    final state = _sessionState.getOrInitializeState(context.session);
    final newMessagesText =
        [...context.requestMessages, ...?context.responseMessages]
            .where(
              (message) => _recentMessageRolesIncluded.contains(message.role),
            )
            .map((message) => message.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();

    if (newMessagesText.isEmpty) {
      return;
    }

    final allMessages = [...state.recentMessagesText, ...newMessagesText];
    state.recentMessagesText = allMessages.length > limit
        ? allMessages.skip(allMessages.length - limit).toList()
        : allMessages;
    _sessionState.saveState(context.session, state);
  }

  /// Function callable by the AI model in on-demand mode.
  Future<String> search(
    String userQuestion, {
    CancellationToken? cancellationToken,
  }) async {
    if (userQuestion.trim().isEmpty) {
      return '';
    }

    final results = await _searchAsync(
      userQuestion,
      cancellationToken ?? CancellationToken.none,
    );
    final materialized = results.toList();
    final outputText = formatResults(materialized);
    final logger = _logger;
    if (logger?.isEnabled(LogLevel.information) == true) {
      logger!.logInformation(
        'TextSearchProvider: Retrieved ${materialized.length} search results.',
      );
      if (logger.isEnabled(LogLevel.trace)) {
        logger.logTrace(
          'TextSearchProvider Input:${sanitizeLogData(userQuestion)}\nOutput:${sanitizeLogData(outputText)}',
        );
      }
    }
    return outputText;
  }

  /// Formats search results into model-consumable text.
  String formatResults(List<TextSearchResult> results) {
    final formatter = _contextFormatter;
    if (formatter != null) {
      return formatter(List<TextSearchResult>.unmodifiable(results));
    }
    if (results.isEmpty) {
      return '';
    }

    final sb = StringBuffer()..writeln(_contextPrompt);
    for (final result in results) {
      final sourceName = result.sourceName;
      if (sourceName != null && sourceName.trim().isNotEmpty) {
        sb.writeln('SourceDocName: $sourceName');
      }
      final sourceLink = result.sourceLink;
      if (sourceLink != null && sourceLink.trim().isNotEmpty) {
        sb.writeln('SourceDocLink: $sourceLink');
      }
      sb.writeln('Contents: ${result.text}');
      sb.writeln('----');
    }
    sb.writeln(_citationsPrompt);
    sb.writeln();
    return sb.toString();
  }

  String sanitizeLogData(String? data) => _redactor.redact(data);

  String _buildSearchInput(
    Iterable<String> recentMessagesText,
    Iterable<ChatMessage> requestMessages,
  ) {
    final messageText = requestMessages
        .map((message) => message.text.trim())
        .where((text) => text.isNotEmpty);
    return [...recentMessagesText, ...messageText].join('\n');
  }

  static TextSearchAsync _validateSearchAsync(TextSearchAsync? searchAsync) {
    if (searchAsync == null) {
      throw ArgumentError.notNull('searchAsync');
    }
    return searchAsync;
  }
}

/// Represents the per-session state of a [TextSearchProvider].
class TextSearchProviderState {
  TextSearchProviderState({List<String>? recentMessagesText})
    : recentMessagesText = recentMessagesText ?? [];

  /// Gets or sets the list of recent message texts retained for multi-turn
  /// search context.
  List<String> recentMessagesText;
}

/// Represents a single retrieved text search result.
class TextSearchResult {
  TextSearchResult({
    this.sourceName,
    this.sourceLink,
    this.text = '',
    this.rawRepresentation,
  });

  /// Gets or sets the display name of the source document.
  String? sourceName;

  /// Gets or sets a link/URL to the source document.
  String? sourceLink;

  /// Gets or sets the textual content of the retrieved chunk.
  String text;

  /// Gets or sets the raw representation of the search result.
  Object? rawRepresentation;
}
