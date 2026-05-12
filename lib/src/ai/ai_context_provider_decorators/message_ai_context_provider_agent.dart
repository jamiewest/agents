import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../abstractions/agent_response.dart';
import '../../abstractions/agent_response_extensions.dart';
import '../../abstractions/agent_response_update.dart';
import '../../abstractions/agent_run_options.dart';
import '../../abstractions/agent_session.dart';
import '../../abstractions/ai_agent.dart';
import '../../abstractions/ai_context_provider.dart';
import '../../abstractions/delegating_ai_agent.dart';
import '../../abstractions/message_ai_context_provider.dart';

/// A delegating AI agent that enriches input messages by invoking a pipeline
/// of [MessageAIContextProvider] instances before delegating to the inner
/// agent, and notifies those providers after the inner agent completes.
class MessageAIContextProviderAgent extends DelegatingAIAgent {
  /// Creates a [MessageAIContextProviderAgent] wrapping [innerAgent] with the
  /// given [providers].
  MessageAIContextProviderAgent(
    AIAgent? innerAgent,
    List<MessageAIContextProvider>? providers,
  ) : _providers = _validateProviders(providers),
      super(innerAgent ?? (throw ArgumentError.notNull('innerAgent')));

  final List<MessageAIContextProvider> _providers;

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final enriched = await _invokeProviders(
      messages,
      session,
      cancellationToken,
    );
    AgentResponse response;
    try {
      response = await innerAgent.run(
        session,
        options,
        cancellationToken: cancellationToken,
        messages: enriched,
      );
    } on Exception catch (ex) {
      await _notifyFailure(session, enriched, ex, cancellationToken);
      rethrow;
    }
    await _notifySuccess(
      session,
      enriched,
      response.messages,
      cancellationToken,
    );
    return response;
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final enriched = await _invokeProviders(
      messages,
      session,
      cancellationToken,
    );
    final updates = <AgentResponseUpdate>[];
    try {
      await for (final update in innerAgent.runStreaming(
        session,
        options,
        cancellationToken: cancellationToken,
        messages: enriched,
      )) {
        updates.add(update);
        yield update;
      }
    } on Exception catch (ex) {
      await _notifyFailure(session, enriched, ex, cancellationToken);
      rethrow;
    }
    final agentResponse = updates.toAgentResponse();
    await _notifySuccess(
      session,
      enriched,
      agentResponse.messages,
      cancellationToken,
    );
  }

  Future<Iterable<ChatMessage>> _invokeProviders(
    Iterable<ChatMessage> messages,
    AgentSession? session,
    CancellationToken? cancellationToken,
  ) async {
    var current = messages;
    for (final provider in _providers) {
      final ctx = MessageInvokingContext(this, session, current);
      current = await provider.invokingMessages(
        ctx,
        cancellationToken: cancellationToken,
      );
    }
    return current;
  }

  Future<void> _notifySuccess(
    AgentSession? session,
    Iterable<ChatMessage> requestMessages,
    Iterable<ChatMessage> responseMessages,
    CancellationToken? cancellationToken,
  ) async {
    final ctx = InvokedContext(
      this,
      session,
      requestMessages,
      responseMessages: responseMessages,
    );
    for (final provider in _providers) {
      await provider.invoked(ctx, cancellationToken: cancellationToken);
    }
  }

  Future<void> _notifyFailure(
    AgentSession? session,
    Iterable<ChatMessage> requestMessages,
    Exception exception,
    CancellationToken? cancellationToken,
  ) async {
    final ctx = InvokedContext(
      this,
      session,
      requestMessages,
      invokeException: exception,
    );
    for (final provider in _providers) {
      await provider.invoked(ctx, cancellationToken: cancellationToken);
    }
  }

  static List<MessageAIContextProvider> _validateProviders(
    List<MessageAIContextProvider>? providers,
  ) {
    if (providers == null) {
      throw ArgumentError.notNull('providers');
    }
    if (providers.isEmpty) {
      throw RangeError.range(
        providers.length,
        1,
        null,
        'providers',
        'At least one MessageAIContextProvider must be provided.',
      );
    }
    return List<MessageAIContextProvider>.of(providers);
  }
}
