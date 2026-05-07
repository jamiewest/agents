import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/microsoft_agents_ai_abstractions/agent_run_context.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';

/// A delegating chat client that enriches input messages, tools, and
/// instructions by invoking a pipeline of [AIContextProvider] instances before
/// delegating to the inner chat client.
class AIContextProviderChatClient extends DelegatingChatClient {
  AIContextProviderChatClient(
    ChatClient? innerClient,
    List<AIContextProvider>? providers,
  ) : _providers = _validateProviders(providers),
      super(innerClient ?? (throw ArgumentError.notNull('innerClient')));

  final List<AIContextProvider> _providers;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final runContext = getRequiredRunContext();
    final enriched = await invokeProviders(
      runContext,
      messages,
      options,
      cancellationToken,
    );

    ChatResponse response;
    try {
      response = await innerClient.getResponse(
        messages: enriched.messages,
        options: enriched.options,
        cancellationToken: cancellationToken,
      );
    } on Exception catch (ex) {
      await notifyProvidersOfFailure(
        runContext,
        enriched.messages,
        ex,
        cancellationToken,
      );
      rethrow;
    }

    await notifyProvidersOfSuccess(
      runContext,
      enriched.messages,
      response.messages,
      cancellationToken,
    );
    return response;
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final runContext = getRequiredRunContext();
    final enriched = await invokeProviders(
      runContext,
      messages,
      options,
      cancellationToken,
    );

    final responseUpdates = <ChatResponseUpdate>[];
    try {
      await for (final update in innerClient.getStreamingResponse(
        messages: enriched.messages,
        options: enriched.options,
        cancellationToken: cancellationToken,
      )) {
        responseUpdates.add(update);
        yield update;
      }
    } on Exception catch (ex) {
      await notifyProvidersOfFailure(
        runContext,
        enriched.messages,
        ex,
        cancellationToken,
      );
      rethrow;
    }

    final chatResponse = _toChatResponse(responseUpdates);
    await notifyProvidersOfSuccess(
      runContext,
      enriched.messages,
      chatResponse.messages,
      cancellationToken,
    );
  }

  static AgentRunContext getRequiredRunContext() {
    return AIAgent.currentRunContext ??
        (throw StateError(
          'AIContextProviderChatClient can only be used within the context of '
          'a running AIAgent. Ensure that the chat client is being invoked as '
          'part of an AIAgent.run or AIAgent.runStreaming call.',
        ));
  }

  Future<({Iterable<ChatMessage> messages, ChatOptions? options})>
  invokeProviders(
    AgentRunContext runContext,
    Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  ) async {
    var aiContext = AIContext()
      ..instructions = options?.instructions
      ..messages = messages
      ..tools = options?.tools;

    for (final provider in _providers) {
      final invokingContext = InvokingContext(
        runContext.agent,
        runContext.session,
        aiContext,
      );
      aiContext = await provider.invoking(
        invokingContext,
        cancellationToken: cancellationToken,
      );
    }

    final enrichedOptions = options?.clone();
    final enrichedMessages = aiContext.messages ?? const <ChatMessage>[];
    var materializedOptions = enrichedOptions;

    final tools = aiContext.tools?.toList();
    if ((enrichedOptions?.tools?.isNotEmpty ?? false) ||
        (tools?.isNotEmpty ?? false)) {
      materializedOptions ??= ChatOptions();
      materializedOptions.tools = tools;
    }

    if (enrichedOptions?.instructions != null ||
        aiContext.instructions != null) {
      materializedOptions ??= ChatOptions();
      materializedOptions.instructions = aiContext.instructions;
    }

    return (messages: enrichedMessages, options: materializedOptions);
  }

  Future<void> notifyProvidersOfSuccess(
    AgentRunContext runContext,
    Iterable<ChatMessage> requestMessages,
    Iterable<ChatMessage> responseMessages,
    CancellationToken? cancellationToken,
  ) async {
    final invokedContext = InvokedContext(
      runContext.agent,
      runContext.session,
      requestMessages,
      responseMessages: responseMessages,
    );

    for (final provider in _providers) {
      await provider.invoked(
        invokedContext,
        cancellationToken: cancellationToken,
      );
    }
  }

  Future<void> notifyProvidersOfFailure(
    AgentRunContext runContext,
    Iterable<ChatMessage> requestMessages,
    Exception exception,
    CancellationToken? cancellationToken,
  ) async {
    final invokedContext = InvokedContext(
      runContext.agent,
      runContext.session,
      requestMessages,
      invokeException: exception,
    );

    for (final provider in _providers) {
      await provider.invoked(
        invokedContext,
        cancellationToken: cancellationToken,
      );
    }
  }

  static List<AIContextProvider> _validateProviders(
    List<AIContextProvider>? providers,
  ) {
    if (providers == null) {
      throw ArgumentError.notNull('providers');
    }
    if (providers.isEmpty) {
      throw ArgumentError(
        'At least one AIContextProvider must be provided.',
        'providers',
      );
    }
    return List<AIContextProvider>.of(providers);
  }

  static ChatResponse _toChatResponse(List<ChatResponseUpdate> updates) {
    final response = ChatResponse();
    ChatMessage? currentMessage;

    for (final update in updates) {
      if (_needsNewMessage(currentMessage, update)) {
        currentMessage = ChatMessage(
          role: update.role ?? ChatRole.assistant,
          authorName: update.authorName,
          contents: [],
        );
        currentMessage.messageId = update.messageId;
        currentMessage.createdAt = update.createdAt;
        currentMessage.rawRepresentation = update.rawRepresentation;
        response.messages.add(currentMessage);
      }

      currentMessage!.contents.addAll(update.contents);

      response.responseId = update.responseId ?? response.responseId;
      response.conversationId =
          update.conversationId ?? response.conversationId;
      response.createdAt = response.createdAt ?? update.createdAt;
      response.finishReason = update.finishReason ?? response.finishReason;
      response.modelId = update.modelId ?? response.modelId;
      response.usage = update.usage ?? response.usage;
      response.continuationToken =
          update.continuationToken ?? response.continuationToken;
      response.rawRepresentation =
          update.rawRepresentation ?? response.rawRepresentation;
      response.additionalProperties =
          update.additionalProperties ?? response.additionalProperties;
    }

    return response;
  }

  static bool _needsNewMessage(
    ChatMessage? currentMessage,
    ChatResponseUpdate update,
  ) {
    return currentMessage == null ||
        currentMessage.role != (update.role ?? ChatRole.assistant) ||
        currentMessage.authorName != update.authorName;
  }
}
