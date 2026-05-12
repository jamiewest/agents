import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'agent_request_message_source_type.dart';
import 'agent_session.dart';
import 'ai_agent.dart';
import 'chat_message_extensions.dart';

/// Provides an abstract base class for fetching and storing chat history
/// messages for use during agent execution.
///
/// A [ChatHistoryProvider] is only relevant when the underlying AI service
/// does not manage chat history itself.
abstract class ChatHistoryProvider {
  /// Creates a [ChatHistoryProvider] with optional message filters.
  ///
  /// [provideOutputMessageFilter] optionally filters messages on retrieval.
  ///
  /// [storeInputRequestMessageFilter] filters request messages before storage;
  /// defaults to [defaultExcludeChatHistoryFilter].
  ///
  /// [storeInputResponseMessageFilter] filters response messages before
  /// storage; defaults to [defaultNoopFilter].
  ChatHistoryProvider({
    Iterable<ChatMessage> Function(Iterable<ChatMessage>)? provideOutputMessageFilter,
    Iterable<ChatMessage> Function(Iterable<ChatMessage>)? storeInputRequestMessageFilter,
    Iterable<ChatMessage> Function(Iterable<ChatMessage>)? storeInputResponseMessageFilter,
  })  : _provideOutputMessageFilter = provideOutputMessageFilter,
        _storeInputRequestMessageFilter =
            storeInputRequestMessageFilter ?? defaultExcludeChatHistoryFilter,
        _storeInputResponseMessageFilter =
            storeInputResponseMessageFilter ?? defaultNoopFilter;

  List<String>? _stateKeys;

  final Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
      _provideOutputMessageFilter;

  final Iterable<ChatMessage> Function(Iterable<ChatMessage>)
      _storeInputRequestMessageFilter;

  final Iterable<ChatMessage> Function(Iterable<ChatMessage>)
      _storeInputResponseMessageFilter;

  static Iterable<ChatMessage> defaultExcludeChatHistoryFilter(
      Iterable<ChatMessage> messages) {
    return messages.where((m) =>
        m.getAgentRequestMessageSourceType() !=
        AgentRequestMessageSourceType.chatHistory);
  }

  static Iterable<ChatMessage> defaultNoopFilter(
          Iterable<ChatMessage> messages) =>
      messages;

  /// The keys used to store provider state in the session [StateBag].
  List<String> get stateKeys =>
      _stateKeys ??= [runtimeType.toString()];

  /// Called at the start of agent invocation to provide messages for context.
  Future<Iterable<ChatMessage>> invoking(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) {
    return invokingCore(context, cancellationToken: cancellationToken);
  }

  /// Core implementation of [invoking]. Retrieves history, applies the
  /// optional output filter, stamps messages, and prepends to request messages.
  Future<Iterable<ChatMessage>> invokingCore(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    Iterable<ChatMessage> output =
        await provideChatHistory(context, cancellationToken: cancellationToken);

    if (_provideOutputMessageFilter != null) {
      output = _provideOutputMessageFilter(output);
    }

    final stamped = output.map((m) => m.withAgentRequestMessageSource(
          AgentRequestMessageSourceType.chatHistory,
          sourceId: runtimeType.toString(),
        ));

    return [...stamped, ...context.requestMessages];
  }

  /// When overridden, returns chat history messages for the current invocation
  /// in chronological order (oldest first).
  Future<Iterable<ChatMessage>> provideChatHistory(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) =>
      Future.value(const []);

  /// Called at the end of the agent invocation to store new messages.
  Future<void> invoked(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) {
    return invokedCore(context, cancellationToken: cancellationToken);
  }

  /// Core implementation of [invoked]. Skips on failure, filters messages,
  /// then calls [storeChatHistory].
  Future<void> invokedCore(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) {
    if (context.invokeException != null) return Future.value();
    final subContext = InvokedContext(
      context.agent,
      context.session,
      _storeInputRequestMessageFilter(context.requestMessages),
      responseMessages: _storeInputResponseMessageFilter(
        context.responseMessages ?? const [],
      ),
    );
    return storeChatHistory(subContext, cancellationToken: cancellationToken);
  }

  /// When overridden, stores new messages at the end of the invocation.
  Future<void> storeChatHistory(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) =>
      Future.value();

  /// Returns a service of the specified [serviceType], or `null`.
  Object? getService(Type serviceType, {Object? serviceKey}) {
    return serviceType == ChatHistoryProvider ? this : null;
  }
}

/// Context passed to [ChatHistoryProvider.invoked].
class InvokedContext {
  InvokedContext(
    this.agent,
    this.session,
    this.requestMessages, {
    this.responseMessages,
    this.invokeException,
  });

  /// The agent that was invoked.
  final AIAgent agent;

  /// The session associated with the agent invocation.
  final AgentSession? session;

  /// The accumulated request messages used by the agent.
  final Iterable<ChatMessage> requestMessages;

  /// The response messages generated during this invocation.
  final Iterable<ChatMessage>? responseMessages;

  /// The exception thrown during the invocation, if any.
  final Exception? invokeException;
}

/// Context passed to [ChatHistoryProvider.invoking].
class InvokingContext {
  InvokingContext(this.agent, this.session, this.requestMessages);

  /// The agent being invoked.
  final AIAgent agent;

  /// The session associated with the agent invocation.
  final AgentSession? session;

  /// The messages to be used by the agent for this invocation.
  Iterable<ChatMessage> requestMessages;
}
