import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_run_context.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';

/// A delegating chat client that enriches input messages, tools, and
/// instructions by invoking a pipeline of [AIContextProvider] instances
/// before delegating to the inner chat client, and notifies those providers
/// after the inner client completes.
///
/// Remarks: This chat client must be used within the context of a running
/// [AIAgent]. It retrieves the current agent and session from
/// [CurrentRunContext], which is set automatically when an agent's
/// [CancellationToken)] or [CancellationToken)] method is called. An
/// [InvalidOperationException] is thrown if no run context is available.
class AIContextProviderChatClient extends DelegatingChatClient {
  /// Initializes a new instance of the [AIContextProviderChatClient] class.
  ///
  /// [innerClient] The underlying chat client that will handle the core
  /// operations.
  ///
  /// [providers] The AI context providers to invoke before and after the inner
  /// chat client.
  AIContextProviderChatClient(
    ChatClient innerClient,
    List<AIContextProvider> providers,
  ) : _providers = providers {
    if (providers.isEmpty) {
      throw ArgumentError('At least one AIContextProvider must be provided.', 'providers');
    }
  }

  final List<AIContextProvider> _providers;

  @override
  Future<ChatResponse> getResponse(
    Iterable<ChatMessage> messages,
    {ChatOptions? options, CancellationToken? cancellationToken, },
  ) async  {
    var runContext = getRequiredRunContext();
    var (
      enrichedMessages,
      enrichedOptions,
    ) = await this.invokeProvidersAsync(runContext, messages, options, cancellationToken);
    ChatResponse response;
    try {
      response = await super.getResponseAsync(
        enrichedMessages,
        enrichedOptions,
        cancellationToken,
      ) ;
    } catch (e, s) {
      if (e is Exception) {
        final ex = e as Exception;
        {
          await this.notifyProvidersOfFailureAsync(
            runContext,
            enrichedMessages,
            ex,
            cancellationToken,
          ) ;
          rethrow;
        }
      } else {
        rethrow;
      }
    }
    await this.notifyProvidersOfSuccessAsync(
      runContext,
      enrichedMessages,
      response.messages,
      cancellationToken,
    ) ;
    return response;
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse(
    Iterable<ChatMessage> messages,
    {ChatOptions? options, CancellationToken? cancellationToken, },
  ) async  {
    var runContext = getRequiredRunContext();
    var (
      enrichedMessages,
      enrichedOptions,
    ) = await this.invokeProvidersAsync(runContext, messages, options, cancellationToken);
    var responseUpdates = [];
    Stream<ChatResponseUpdate> enumerator;
    try {
      enumerator = super.getStreamingResponseAsync(
        enrichedMessages,
        enrichedOptions,
        cancellationToken,
      ) .getAsyncEnumerator(cancellationToken);
    } catch (e, s) {
      if (e is Exception) {
        final ex = e as Exception;
        {
          await this.notifyProvidersOfFailureAsync(
            runContext,
            enrichedMessages,
            ex,
            cancellationToken,
          ) ;
          rethrow;
        }
      } else {
        rethrow;
      }
    }
    bool hasUpdates;
    try {
      hasUpdates = await enumerator.moveNextAsync();
    } catch (e, s) {
      if (e is Exception) {
        final ex = e as Exception;
        {
          await this.notifyProvidersOfFailureAsync(
            runContext,
            enrichedMessages,
            ex,
            cancellationToken,
          ) ;
          rethrow;
        }
      } else {
        rethrow;
      }
    }
    while (hasUpdates) {
      var update = enumerator.current;
      responseUpdates.add(update);
      yield update;
      try {
        hasUpdates = await enumerator.moveNextAsync();
      } catch (e, s) {
        if (e is Exception) {
          final ex = e as Exception;
          {
            await this.notifyProvidersOfFailureAsync(
              runContext,
              enrichedMessages,
              ex,
              cancellationToken,
            ) ;
            rethrow;
          }
        } else {
          rethrow;
        }
      }
    }
    var chatResponse = responseUpdates.toChatResponse();
    await this.notifyProvidersOfSuccessAsync(
      runContext,
      enrichedMessages,
      chatResponse.messages,
      cancellationToken,
    ) ;
  }

  /// Gets the current [AgentRunContext], throwing if not available.
  static AgentRunContext getRequiredRunContext() {
    return AIAgent.currentRunContext
            ?? throw StateError(
                '${'AIContextProviderChatClient'} can only be used within the context of a running AIAgent. ' +
                "Ensure that the chat client is being invoked as part of an AIAgent.runAsync or AIAgent.runStreamingAsync call.");
  }

  /// Invokes each provider's [CancellationToken)] in sequence, accumulating
  /// context (messages, tools, instructions) from each.
  Future<EnumerableChatMessageMessages, ChatOptionsOptions> invokeProviders(
    AgentRunContext runContext,
    Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken cancellationToken,
  ) async  {
    var aiContext = AIContext();
    for (final provider in this._providers) {
      var invokingContext = invokingContext(runContext.agent, runContext.session, aiContext);
      aiContext = await provider.invoking(
        invokingContext,
        cancellationToken,
      ) ;
    }
    // Materialize the accumulated context back into messages and options.
        // Clone options to avoid mutating the caller's instance across calls.
        options = options?.clone();
    var enrichedMessages = aiContext.messages ?? [];
    var tools = aiContext.tools as IList<AITool> ?? aiContext.tools?.toList();
    if (options?.tools ?.isNotEmpty == true || tools ?.isNotEmpty == true) {
      options ??= new();
      options.tools = tools;
    }
    if (options?.instructions != null|| aiContext.instructions != null) {
      options ??= new();
      options.instructions = aiContext.instructions;
    }
    return (enrichedMessages, options);
  }

  /// Notifies each provider of a successful invocation.
  Future notifyProvidersOfSuccess(
    AgentRunContext runContext,
    Iterable<ChatMessage> requestMessages,
    Iterable<ChatMessage> responseMessages,
    CancellationToken cancellationToken,
  ) async  {
    var invokedContext = invokedContext(
      runContext.agent,
      runContext.session,
      requestMessages,
      responseMessages,
    );
    for (final provider in this._providers) {
      await provider.invoked(invokedContext, cancellationToken);
    }
  }

  /// Notifies each provider of a failed invocation.
  Future notifyProvidersOfFailure(
    AgentRunContext runContext,
    Iterable<ChatMessage> requestMessages,
    Exception exception,
    CancellationToken cancellationToken,
  ) async  {
    var invokedContext = invokedContext(
      runContext.agent,
      runContext.session,
      requestMessages,
      exception,
    );
    for (final provider in this._providers) {
      await provider.invoked(invokedContext, cancellationToken);
    }
  }
}
