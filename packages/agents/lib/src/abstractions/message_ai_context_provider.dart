import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'agent_request_message_source_type.dart';
import 'agent_session.dart';
import 'ai_agent.dart';
import 'ai_context.dart';
import 'ai_context_provider.dart';
import 'chat_message_extensions.dart';

/// Abstract base class for components that enhance AI context during agent
/// invocations by supplying additional chat messages.
///
/// Participates in the agent invocation lifecycle by providing additional
/// messages that are merged with the input. Overrides [provideAIContext] to
/// wrap the returned messages in an [AIContext].
abstract class MessageAIContextProvider extends AIContextProvider {
  /// Creates a [MessageAIContextProvider] with optional message filters.
  MessageAIContextProvider({
    super.provideInputMessageFilter,
    super.storeInputRequestMessageFilter,
    super.storeInputResponseMessageFilter,
  });

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final inputMessages = context.aiContext.messages ?? const <ChatMessage>[];
    final messageContext = MessageInvokingContext(
      context.agent,
      context.session,
      inputMessages,
    );
    final messages = await invokingMessages(
      messageContext,
      cancellationToken: cancellationToken,
    );
    return AIContext()..messages = messages;
  }

  /// Core message pipeline: filters input, calls [provideMessages], stamps
  /// source attribution, and merges with the original input.
  ///
  /// Override this for full control over the merged message list. Override
  /// [provideMessages] for just the additional messages to inject.
  Future<Iterable<ChatMessage>> invokingMessages(
    MessageInvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final inputMessages = context.requestMessages;
    final filteredContext = MessageInvokingContext(
      context.agent,
      context.session,
      provideInputMessageFilter(inputMessages),
    );
    final provided = await provideMessages(
      filteredContext,
      cancellationToken: cancellationToken,
    );
    final stamped = provided.map(
      (m) => m.withAgentRequestMessageSource(
        AgentRequestMessageSourceType.aiContextProvider,
        sourceId: runtimeType.toString(),
      ),
    );
    return [...inputMessages, ...stamped];
  }

  /// When overridden in a derived class, returns additional messages to merge
  /// into the input for the current invocation.
  Future<Iterable<ChatMessage>> provideMessages(
    MessageInvokingContext context, {
    CancellationToken? cancellationToken,
  }) {
    return Future.value(const <ChatMessage>[]);
  }
}

/// Context passed to [MessageAIContextProvider.invoking].
class MessageInvokingContext {
  /// Creates a [MessageInvokingContext].
  MessageInvokingContext(this.agent, this.session, this.requestMessages);

  /// The agent being invoked.
  final AIAgent agent;

  /// The session associated with the agent invocation.
  final AgentSession? session;

  /// The messages that will be used by the agent for this invocation.
  Iterable<ChatMessage> requestMessages;
}
