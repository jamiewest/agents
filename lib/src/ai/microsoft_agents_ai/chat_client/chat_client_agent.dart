import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent_metadata.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart'
    as acp;
import '../../../abstractions/microsoft_agents_ai_abstractions/chat_history_provider.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/in_memory_chat_history_provider.dart';
import 'chat_client_agent_continuation_token.dart';
import 'chat_client_agent_log_messages.dart';
import 'chat_client_agent_options.dart';
import 'chat_client_agent_run_options.dart';
import 'chat_client_agent_session.dart';
import 'per_service_call_chat_history_persisting_chat_client.dart';

/// Provides an [AIAgent] that delegates to a [ChatClient] implementation.
///
/// Security considerations: The [ChatClientAgent] orchestrates data flow
/// across trust boundaries. The underlying AI service is an external endpoint
/// and LLM responses should be treated as untrusted output. Developers should
/// be aware of prompt injection, hallucinations, malicious payloads in LLM
/// output, and untrusted function arguments. Apply defense-in-depth by
/// combining tool approval requirements with output validation.
final class ChatClientAgent extends AIAgent {
  late final ChatClientAgentOptions? _agentOptions;
  late final Set<String> _aiContextProviderStateKeys;
  late final AIAgentMetadata _agentMetadata;
  late final Logger _logger;
  late final Type _chatClientType;

  /// Gets the underlying chat client used by the agent.
  late final ChatClient chatClient;

  /// Gets the [ChatHistoryProvider] used by this agent.
  ChatHistoryProvider? chatHistoryProvider;

  /// Gets the list of [acp.AIContextProvider] instances used by this agent.
  late final List<acp.AIContextProvider>? aiContextProviders;

  /// Initializes a new [ChatClientAgent] with the specified chat client and
  /// options.
  ChatClientAgent(
    ChatClient chatClient_, {
    ChatClientAgentOptions? options,
    LoggerFactory? loggerFactory,
    Object? services,
  }) {
    _agentOptions = options?.clone();
    _agentMetadata = AIAgentMetadata(
      providerName: chatClient_.getService<ChatClientMetadata>()?.providerName,
    );
    _chatClientType = chatClient_.runtimeType;
    // TODO: apply chatClient_.withDefaultAgentMiddleware(options, services)
    // once that extension is implemented.
    chatClient = chatClient_;
    chatHistoryProvider =
        _agentOptions?.chatHistoryProvider ?? InMemoryChatHistoryProvider();
    aiContextProviders = _agentOptions?.aiContextProviders?.toList();
    _aiContextProviderStateKeys = _validateAndCollectStateKeys(
      _agentOptions?.aiContextProviders,
      chatHistoryProvider,
    );
    _logger = (loggerFactory ??
            chatClient.getService<LoggerFactory>() ??
            NullLoggerFactory.instance)
        .createLogger('ChatClientAgent');
    _warnOnMissingPerServiceCallChatHistoryPersistingChatClient();
  }

  /// Convenience constructor accepting individual agent settings.
  factory ChatClientAgent.withSettings(
    ChatClient chatClient, {
    String? instructions,
    String? name,
    String? description,
    List<AITool>? tools,
    LoggerFactory? loggerFactory,
    Object? services,
  }) {
    final opts = ChatClientAgentOptions();
    opts.name = name;
    opts.description = description;
    if (tools != null || instructions != null) {
      opts.chatOptions = ChatOptions(
        tools: tools,
        instructions: instructions,
      );
    }
    return ChatClientAgent(
      chatClient,
      options: opts,
      loggerFactory: loggerFactory,
      services: services,
    );
  }

  String? get idCore => _agentOptions?.id;

  String? get name => _agentOptions?.name;

  String? get description => _agentOptions?.description;

  /// Gets the system instructions for this agent.
  String? get instructions => _agentOptions?.chatOptions?.instructions;

  /// Gets the default [ChatOptions] used by the agent.
  ChatOptions? get chatOptions => _agentOptions?.chatOptions;

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final inputMessages =
        messages is List<ChatMessage> ? messages : messages.toList();

    final (safeSession, chatOpts, inputMessagesForClient, _) =
        await _prepareSessionAndMessages(
      session,
      inputMessages,
      options,
      cancellationToken,
    );

    _ensureRunContextHasSession(safeSession);

    var client = chatClient;
    client = _applyRunOptionsTransformations(options, client);

    final agentName = _getLoggingAgentName();
    _logger.logAgentChatClientInvokingAgent(
      'runAsync',
      id,
      agentName,
      _chatClientType,
    );

    late ChatResponse chatResponse;
    try {
      chatResponse = await client.getResponse(
        messages: inputMessagesForClient,
        options: chatOpts,
        cancellationToken: cancellationToken,
      );
    } catch (ex) {
      await _notifyProvidersOfFailureAtEndOfRun(
        safeSession,
        ex is Exception ? ex : Exception(ex.toString()),
        inputMessagesForClient,
        chatOpts,
        cancellationToken,
      );
      rethrow;
    }

    _logger.logAgentChatClientInvokedAgent(
      'runAsync',
      id,
      agentName,
      _chatClientType,
      inputMessages.length,
    );

    final forceEndOfRunPersistence = chatOpts?.continuationToken != null ||
        chatOpts?.allowBackgroundResponses == true;

    _updateSessionConversationIdAtEndOfRun(
      safeSession,
      chatResponse.conversationId,
      cancellationToken,
      forceUpdate: forceEndOfRunPersistence,
    );

    for (final msg in chatResponse.messages) {
      msg.authorName ??= name;
    }

    await _notifyProvidersOfNewMessagesAtEndOfRun(
      safeSession,
      inputMessagesForClient,
      chatResponse.messages,
      chatOpts,
      cancellationToken,
      forceNotify: forceEndOfRunPersistence,
    );

    return AgentResponse(response: chatResponse)
      ..agentId = id
      ..continuationToken =
          _wrapContinuationToken(chatResponse.continuationToken);
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final inputMessages =
        messages is List<ChatMessage> ? messages : messages.toList();

    final (safeSession, chatOpts, inputMessagesForClient, continuationToken) =
        await _prepareSessionAndMessages(
      session,
      inputMessages,
      options,
      cancellationToken,
    );

    _ensureRunContextHasSession(safeSession);

    var client = chatClient;
    client = _applyRunOptionsTransformations(options, client);

    final agentName = _getLoggingAgentName();
    _logger.logAgentChatClientInvokingAgent(
      'runStreamingAsync',
      id,
      agentName,
      _chatClientType,
    );

    final responseUpdates = _getResponseUpdates(continuationToken);

    _logger.logAgentChatClientInvokedStreamingAgent(
      'runStreamingAsync',
      id,
      agentName,
      _chatClientType,
    );

    try {
      await for (final update in client.getStreamingResponse(
        messages: inputMessagesForClient,
        options: chatOpts,
        cancellationToken: cancellationToken,
      )) {
        update.authorName ??= name;
        responseUpdates.add(update);
        yield AgentResponseUpdate(chatResponseUpdate: update)
          ..agentId = id
          ..continuationToken = _wrapContinuationToken(
            update.continuationToken,
            inputMessages: _getInputMessages(inputMessages, continuationToken),
            responseUpdates: responseUpdates,
          );
        _ensureRunContextHasSession(safeSession);
      }
    } catch (ex) {
      await _notifyProvidersOfFailureAtEndOfRun(
        safeSession,
        ex is Exception ? ex : Exception(ex.toString()),
        _getInputMessages(inputMessagesForClient, continuationToken),
        chatOpts,
        cancellationToken,
      );
      rethrow;
    }

    final chatResponse = _buildChatResponse(responseUpdates);
    final forceEndOfRunPersistence = continuationToken != null ||
        chatOpts?.allowBackgroundResponses == true;

    _updateSessionConversationIdAtEndOfRun(
      safeSession,
      chatResponse.conversationId,
      cancellationToken,
      forceUpdate: forceEndOfRunPersistence,
    );

    await _notifyProvidersOfNewMessagesAtEndOfRun(
      safeSession,
      _getInputMessages(inputMessagesForClient, continuationToken),
      chatResponse.messages,
      chatOpts,
      cancellationToken,
      forceNotify: forceEndOfRunPersistence,
    );
  }

  @override
  Object? getService(Type serviceType, {Object? serviceKey}) {
    return super.getService(serviceType, serviceKey: serviceKey) ??
        (serviceType == AIAgentMetadata
            ? _agentMetadata
            : serviceType == ChatClient
                ? chatClient
                : serviceType == ChatOptions
                    ? _agentOptions?.chatOptions
                    : serviceType == ChatClientAgentOptions
                        ? _agentOptions
                        : aiContextProviders
                                ?.map((p) => p.getService(serviceType,
                                    serviceKey: serviceKey))
                                .where((s) => s != null)
                                .firstOrNull ??
                            chatHistoryProvider?.getService(serviceType,
                                serviceKey: serviceKey));
  }

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    dynamic JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    if (session is ChatClientAgentSession) {
      return session.serialize();
    }
    throw ArgumentError.value(session, 'session', 'Unsupported session type.');
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    dynamic JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    if (serializedState is String) {
      return ChatClientAgentSession.deserialize(serializedState);
    }
    throw ArgumentError.value(
      serializedState,
      'serializedState',
      'Expected a JSON String.',
    );
  }

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async =>
      ChatClientAgentSession();

  /// Creates a session that continues an existing conversation by id.
  Future<ChatClientAgentSession> createSessionWithConversationId(
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async =>
      ChatClientAgentSession(conversationId: conversationId);

  // ---------------------------------------------------------------------------
  // Internal helpers (accessible to PerServiceCallChatHistoryPersistingChatClient)
  // ---------------------------------------------------------------------------

  Future<void> notifyProvidersOfNewMessages(
    ChatClientAgentSession session,
    Iterable<ChatMessage> requestMessages,
    Iterable<ChatMessage> responseMessages,
    ChatOptions? chatOpts,
    CancellationToken? cancellationToken,
  ) async {
    final provider = _resolveChatHistoryProvider(chatOpts);
    if (provider != null) {
      final ctx = InvokedContext(
        this,
        session,
        requestMessages,
        responseMessages: responseMessages,
      );
      await provider.invoked(ctx, cancellationToken: cancellationToken);
    }

    final providers = aiContextProviders;
    if (providers != null && providers.isNotEmpty) {
      final ctx = acp.InvokedContext(
        this,
        session,
        requestMessages,
        responseMessages: responseMessages,
      );
      for (final p in providers) {
        await p.invoked(ctx, cancellationToken: cancellationToken);
      }
    }
  }

  Future<void> notifyProvidersOfFailure(
    ChatClientAgentSession session,
    Exception ex,
    Iterable<ChatMessage> requestMessages,
    ChatOptions? chatOpts,
    CancellationToken? cancellationToken,
  ) async {
    final provider = _resolveChatHistoryProvider(chatOpts);
    if (provider != null) {
      final ctx = InvokedContext(
        this,
        session,
        requestMessages,
        invokeException: ex,
      );
      await provider.invoked(ctx, cancellationToken: cancellationToken);
    }

    final providers = aiContextProviders;
    if (providers != null && providers.isNotEmpty) {
      final ctx = acp.InvokedContext(
        this,
        session,
        requestMessages,
        invokeException: ex,
      );
      for (final p in providers) {
        await p.invoked(ctx, cancellationToken: cancellationToken);
      }
    }
  }

  Future<Iterable<ChatMessage>> loadChatHistory(
    ChatClientAgentSession session,
    Iterable<ChatMessage> messages,
    ChatOptions? chatOpts,
    CancellationToken? cancellationToken,
  ) async {
    final provider = _resolveChatHistoryProvider(chatOpts);
    if (provider == null) return messages;
    final ctx = InvokingContext(this, session, messages);
    return provider.invoking(ctx, cancellationToken: cancellationToken);
  }

  void updateSessionConversationId(
    ChatClientAgentSession session,
    String? responseConversationId,
    CancellationToken? cancellationToken,
  ) {
    if ((responseConversationId == null || responseConversationId.isEmpty) &&
        session.conversationId != null &&
        session.conversationId!.isNotEmpty) {
      throw StateError(
        'Service did not return a valid conversation id when using an '
        'AgentSession with service managed chat history.',
      );
    }

    if (responseConversationId != null && responseConversationId.isNotEmpty) {
      final agentChatHistoryProvider = _agentOptions?.chatHistoryProvider;
      if (agentChatHistoryProvider != null) {
        if (_agentOptions?.warnOnChatHistoryProviderConflict == true &&
            _logger.isEnabled(LogLevel.warning)) {
          _logger.logAgentChatClientHistoryProviderConflict(
            'conversationId',
            'chatHistoryProvider',
            id,
            _getLoggingAgentName(),
          );
        }
        if (_agentOptions?.throwOnChatHistoryProviderConflict == true) {
          throw StateError(
            'Only conversationId or chatHistoryProvider may be used, but not '
            'both. The service returned a conversation id indicating '
            'server-side chat history management, but the agent has a '
            'chatHistoryProvider configured.',
          );
        }
        if (_agentOptions?.clearOnChatHistoryProviderConflict == true) {
          chatHistoryProvider = null;
        }
      }
      session.conversationId = responseConversationId;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static ChatClient _applyRunOptionsTransformations(
    AgentRunOptions? options,
    ChatClient client,
  ) {
    if (options is ChatClientAgentRunOptions) {
      final factory = options.chatClientFactory;
      if (factory != null) {
        final transformed = factory(client);
        return transformed;
      }
    }
    return client;
  }

  (ChatOptions?, ChatClientAgentContinuationToken?) _createConfiguredChatOptions(
    AgentRunOptions? runOptions,
  ) {
    ChatOptions? requestChatOptions;
    if (runOptions is ChatClientAgentRunOptions) {
      requestChatOptions = runOptions.chatOptions?.clone();
    }

    if (_agentOptions?.chatOptions == null) {
      return _applyAgentRunOptionsOverrides(requestChatOptions, runOptions);
    }
    if (requestChatOptions == null) {
      return _applyAgentRunOptionsOverrides(
        _agentOptions?.chatOptions?.clone(),
        runOptions,
      );
    }

    final agentOpts = _agentOptions!.chatOptions!;
    requestChatOptions.allowMultipleToolCalls ??= agentOpts.allowMultipleToolCalls;
    requestChatOptions.conversationId ??= agentOpts.conversationId;
    requestChatOptions.frequencyPenalty ??= agentOpts.frequencyPenalty;
    requestChatOptions.maxOutputTokens ??= agentOpts.maxOutputTokens;
    requestChatOptions.modelId ??= agentOpts.modelId;
    requestChatOptions.presencePenalty ??= agentOpts.presencePenalty;
    requestChatOptions.responseFormat ??= agentOpts.responseFormat;
    requestChatOptions.seed ??= agentOpts.seed;
    requestChatOptions.temperature ??= agentOpts.temperature;
    requestChatOptions.topP ??= agentOpts.topP;
    requestChatOptions.topK ??= agentOpts.topK;
    requestChatOptions.toolMode ??= agentOpts.toolMode;

    final reqInstr = requestChatOptions.instructions;
    final agentInstr = instructions;
    if ((reqInstr != null && reqInstr.isNotEmpty) &&
        (agentInstr != null && agentInstr.isNotEmpty)) {
      requestChatOptions.instructions = '$agentInstr\n$reqInstr';
    } else {
      requestChatOptions.instructions =
          (reqInstr != null && reqInstr.isNotEmpty) ? reqInstr : agentInstr;
    }

    final agentAdditional = agentOpts.additionalProperties;
    if (requestChatOptions.additionalProperties != null &&
        agentAdditional != null) {
      for (final entry in agentAdditional.entries) {
        requestChatOptions.additionalProperties!.putIfAbsent(
          entry.key,
          () => entry.value,
        );
      }
    } else {
      requestChatOptions.additionalProperties ??=
          agentAdditional != null ? Map.of(agentAdditional) : null;
    }

    final agentFactory = agentOpts.rawRepresentationFactory;
    if (agentFactory != null) {
      final requestFactory = requestChatOptions.rawRepresentationFactory;
      requestChatOptions.rawRepresentationFactory = requestFactory != null
          ? (c) => requestFactory(c) ?? agentFactory(c)
          : agentFactory;
    }

    final agentStop = agentOpts.stopSequences;
    if (agentStop != null && agentStop.isNotEmpty) {
      final reqStop = requestChatOptions.stopSequences;
      if (reqStop == null || reqStop.isEmpty) {
        requestChatOptions.stopSequences = List.of(agentStop);
      } else if (reqStop is List<String>) {
        reqStop.addAll(agentStop);
      } else {
        for (final s in agentStop) {
          requestChatOptions.stopSequences!.add(s);
        }
      }
    }

    final agentTools = agentOpts.tools;
    if (agentTools != null && agentTools.isNotEmpty) {
      final reqTools = requestChatOptions.tools;
      if (reqTools == null || reqTools.isEmpty) {
        requestChatOptions.tools = List.of(agentTools);
      } else if (reqTools is List<AITool>) {
        reqTools.addAll(agentTools);
      } else {
        for (final t in agentTools) {
          requestChatOptions.tools!.add(t);
        }
      }
    }

    return _applyAgentRunOptionsOverrides(requestChatOptions, runOptions);
  }

  static (ChatOptions?, ChatClientAgentContinuationToken?)
      _applyAgentRunOptionsOverrides(
    ChatOptions? chatOptions,
    AgentRunOptions? agentRunOptions,
  ) {
    if (agentRunOptions?.allowBackgroundResponses != null) {
      chatOptions ??= ChatOptions();
      chatOptions.allowBackgroundResponses = agentRunOptions!.allowBackgroundResponses;
    }

    if (agentRunOptions?.responseFormat != null) {
      chatOptions ??= ChatOptions();
      chatOptions.responseFormat = agentRunOptions!.responseFormat;
    }

    ChatClientAgentContinuationToken? agentContinuationToken;
    final rawToken =
        agentRunOptions?.continuationToken ?? chatOptions?.continuationToken;
    if (rawToken != null) {
      agentContinuationToken = ChatClientAgentContinuationToken.fromToken(rawToken);
      chatOptions ??= ChatOptions();
      chatOptions.continuationToken = agentContinuationToken.innerToken;
    }

    final additionalProps = agentRunOptions?.additionalProperties;
    if (additionalProps != null && additionalProps.isNotEmpty) {
      chatOptions ??= ChatOptions();
      chatOptions.additionalProperties ??= {};
      for (final entry in additionalProps.entries) {
        chatOptions.additionalProperties![entry.key] = entry.value;
      }
    }

    return (chatOptions, agentContinuationToken);
  }

  Future<
      (
        ChatClientAgentSession,
        ChatOptions?,
        List<ChatMessage>,
        ChatClientAgentContinuationToken?,
      )> _prepareSessionAndMessages(
    AgentSession? session,
    Iterable<ChatMessage> inputMessages,
    AgentRunOptions? runOptions,
    CancellationToken? cancellationToken,
  ) async {
    final (chatOpts, continuationToken) =
        _createConfiguredChatOptions(runOptions);

    if (chatOpts?.allowBackgroundResponses == true && session == null) {
      throw StateError(
        'A session must be provided when continuing a background response '
        'with a continuation token.',
      );
    }

    if ((continuationToken != null ||
            chatOpts?.allowBackgroundResponses == true) &&
        _requiresPerServiceCallChatHistoryPersistence &&
        _logger.isEnabled(LogLevel.warning)) {
      _logger.logAgentChatClientBackgroundResponseFallback(
        id,
        _getLoggingAgentName(),
      );
    }

    final resolvedSession =
        session ?? await createSessionCore(cancellationToken: cancellationToken);
    if (resolvedSession is! ChatClientAgentSession) {
      throw StateError(
        "The provided session type ${resolvedSession.runtimeType} is not "
        "compatible with this agent. Only ChatClientAgentSession can be used.",
      );
    }
    final typedSession = resolvedSession;

    if (chatOpts?.continuationToken != null && inputMessages.isNotEmpty) {
      throw StateError(
        'Input messages are not allowed when continuing a background response '
        'using a continuation token.',
      );
    }

    final sessionConvId = typedSession.conversationId;
    final optsConvId = chatOpts?.conversationId;
    if (sessionConvId != null &&
        sessionConvId.isNotEmpty &&
        optsConvId != null &&
        optsConvId.isNotEmpty &&
        sessionConvId != optsConvId) {
      throw StateError(
        'The conversationId provided via chatOptions is different from the id '
        'of the provided AgentSession. Only one id can be used for a run.',
      );
    }

    if (sessionConvId != null &&
        sessionConvId.isNotEmpty &&
        sessionConvId != chatOpts?.conversationId) {
      final updated = chatOpts ?? ChatOptions();
      updated.conversationId = sessionConvId;
    }

    Iterable<ChatMessage> messagesForClient = inputMessages;

    if (chatOpts?.continuationToken == null &&
        !_requiresPerServiceCallChatHistoryPersistence) {
      messagesForClient = await loadChatHistory(
        typedSession,
        messagesForClient,
        chatOpts,
        cancellationToken,
      );
    }

    if (chatOpts?.continuationToken == null) {
      final providers = aiContextProviders;
      if (providers != null && providers.isNotEmpty) {
        var aiContext = AIContext()
          ..instructions = chatOpts?.instructions
          ..messages = messagesForClient
          ..tools = chatOpts?.tools;

        for (final provider in providers) {
          final ctx = acp.InvokingContext(this, typedSession, aiContext);
          aiContext =
              await provider.invoking(ctx, cancellationToken: cancellationToken);
        }

        messagesForClient = aiContext.messages ?? [];

        final tools = aiContext.tools;
        if ((chatOpts?.tools != null && chatOpts!.tools!.isNotEmpty) ||
            (tools != null && tools.isNotEmpty)) {
          final updated = chatOpts ?? ChatOptions();
          updated.tools = tools?.toList();
        }

        if (chatOpts?.instructions != null || aiContext.instructions != null) {
          final updated = chatOpts ?? ChatOptions();
          updated.instructions = aiContext.instructions;
        }
      }
    }

    final messagesList = messagesForClient is List<ChatMessage>
        ? messagesForClient
        : messagesForClient.toList();

    return (typedSession, chatOpts, messagesList, continuationToken);
  }

  void _updateSessionConversationIdAtEndOfRun(
    ChatClientAgentSession session,
    String? responseConversationId,
    CancellationToken? cancellationToken, {
    bool forceUpdate = false,
  }) {
    if (!forceUpdate && _requiresPerServiceCallChatHistoryPersistence) return;
    updateSessionConversationId(session, responseConversationId, cancellationToken);
  }

  Future<void> _notifyProvidersOfNewMessagesAtEndOfRun(
    ChatClientAgentSession session,
    Iterable<ChatMessage> requestMessages,
    Iterable<ChatMessage> responseMessages,
    ChatOptions? chatOpts,
    CancellationToken? cancellationToken, {
    bool forceNotify = false,
  }) {
    if (!forceNotify && _requiresPerServiceCallChatHistoryPersistence) {
      return Future.value();
    }
    return notifyProvidersOfNewMessages(
      session,
      requestMessages,
      responseMessages,
      chatOpts,
      cancellationToken,
    );
  }

  Future<void> _notifyProvidersOfFailureAtEndOfRun(
    ChatClientAgentSession session,
    Exception ex,
    Iterable<ChatMessage> requestMessages,
    ChatOptions? chatOpts,
    CancellationToken? cancellationToken,
  ) {
    if (_requiresPerServiceCallChatHistoryPersistence) return Future.value();
    return notifyProvidersOfFailure(
      session,
      ex,
      requestMessages,
      chatOpts,
      cancellationToken,
    );
  }

  bool get _requiresPerServiceCallChatHistoryPersistence =>
      _agentOptions?.requirePerServiceCallChatHistoryPersistence == true;

  static void _ensureRunContextHasSession(ChatClientAgentSession safeSession) {
    // TODO: update AIAgent.currentRunContext once AgentRunContext is fully
    // implemented (requires ReadOnlyCollection and other C# artifacts to be
    // ported).
  }

  static ChatResponse _buildChatResponse(
    List<ChatResponseUpdate> updates,
  ) {
    final messages = <ChatMessage>[];
    ChatMessage? current;

    for (final update in updates) {
      final needsNew = current == null ||
          current.role != (update.role ?? ChatRole.assistant) ||
          current.authorName != update.authorName;
      if (needsNew) {
        current = ChatMessage(
          role: update.role ?? ChatRole.assistant,
          authorName: update.authorName,
          contents: [],
        );
        messages.add(current);
      }
      current!.contents.addAll(update.contents);
    }

    return ChatResponse(
      messages: messages,
      conversationId: updates.lastOrNull?.conversationId,
      finishReason: updates.lastOrNull?.finishReason,
      continuationToken: updates.lastOrNull?.continuationToken,
    );
  }

  void _warnOnMissingPerServiceCallChatHistoryPersistingChatClient() {
    if (_agentOptions?.useProvidedChatClientAsIs != true) return;
    if (_agentOptions?.requirePerServiceCallChatHistoryPersistence != true) {
      return;
    }
    final persistingClient =
        chatClient.getService<PerServiceCallChatHistoryPersistingChatClient>();
    if (persistingClient == null && _logger.isEnabled(LogLevel.warning)) {
      _logger.logAgentChatClientMissingPersistingClient(
        id,
        _getLoggingAgentName(),
      );
    }
  }

  ChatHistoryProvider? _resolveChatHistoryProvider(ChatOptions? chatOpts) {
    ChatHistoryProvider? provider =
        chatOpts?.conversationId == null ? chatHistoryProvider : null;

    // Check additionalProperties for a ChatHistoryProvider override.
    final overrideProvider =
        chatOpts?.additionalProperties?['ChatHistoryProvider']
            as ChatHistoryProvider?;
    if (overrideProvider != null) {
      if (_agentOptions?.throwOnChatHistoryProviderConflict == true &&
          chatOpts?.conversationId != null &&
          chatOpts!.conversationId!.isNotEmpty) {
        throw StateError(
          'Only conversationId or chatHistoryProvider may be used, but not '
          'both. The current session has a conversationId indicating '
          'server-side chat history management, but an override '
          'chatHistoryProvider was provided.',
        );
      }
      for (final key in overrideProvider.stateKeys) {
        if (_aiContextProviderStateKeys.contains(key)) {
          throw StateError(
            "The ChatHistoryProvider ${overrideProvider.runtimeType} uses "
            'state key "$key" which is already used by one of the configured '
            'AIContextProviders.',
          );
        }
      }
      provider = overrideProvider;
    }

    return provider;
  }

  static ChatClientAgentContinuationToken? _wrapContinuationToken(
    ResponseContinuationToken? continuationToken, {
    Iterable<ChatMessage>? inputMessages,
    List<ChatResponseUpdate>? responseUpdates,
  }) {
    if (continuationToken == null) return null;
    return ChatClientAgentContinuationToken(continuationToken)
      ..inputMessages = (inputMessages?.isNotEmpty == true) ? inputMessages : null
      ..responseUpdates =
          (responseUpdates != null && responseUpdates.isNotEmpty)
              ? responseUpdates
              : null;
  }

  static Iterable<ChatMessage> _getInputMessages(
    List<ChatMessage> inputMessages,
    ChatClientAgentContinuationToken? token,
  ) {
    if (inputMessages.isNotEmpty) return inputMessages;
    return token?.inputMessages ?? const [];
  }

  static List<ChatResponseUpdate> _getResponseUpdates(
    ChatClientAgentContinuationToken? token,
  ) =>
      token?.responseUpdates?.toList() ?? [];

  String _getLoggingAgentName() => name ?? 'UnnamedAgent';

  static Set<String> _validateAndCollectStateKeys(
    Iterable<acp.AIContextProvider>? aiContextProviders,
    ChatHistoryProvider? chatHistoryProvider,
  ) {
    final stateKeys = <String>{};

    if (aiContextProviders != null) {
      for (final provider in aiContextProviders) {
        for (final key in provider.stateKeys) {
          if (!stateKeys.add(key)) {
            throw StateError(
              "Multiple providers use the same state key '$key'. Each provider "
              'must use a unique state key to avoid overwriting each other\'s '
              'state.',
            );
          }
        }
      }
    }

    if (chatHistoryProvider == null &&
        stateKeys.contains('InMemoryChatHistoryProvider')) {
      throw StateError(
        "The default InMemoryChatHistoryProvider uses the state key "
        "'InMemoryChatHistoryProvider', which is already used by one of the "
        'configured AIContextProviders.',
      );
    }

    if (chatHistoryProvider != null) {
      for (final key in chatHistoryProvider.stateKeys) {
        if (stateKeys.contains(key)) {
          throw StateError(
            "The ChatHistoryProvider ${chatHistoryProvider.runtimeType} uses "
            'state key "$key" which is already used by one of the configured '
            'AIContextProviders.',
          );
        }
      }
    }

    return stateKeys;
  }
}
