import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'agent_request_message_source_type.dart';
import 'agent_session.dart';
import 'ai_agent.dart';
import 'ai_context.dart';
import 'chat_message_extensions.dart';

/// Provides an abstract base class for components that enhance AI context
/// during agent invocations.
abstract class AIContextProvider {
  /// Creates an [AIContextProvider] with optional message filters.
  ///
  /// [provideInputMessageFilter] filters input messages before providing
  /// context. Defaults to [defaultExternalOnlyFilter].
  ///
  /// [storeInputRequestMessageFilter] filters request messages before storing
  /// context. Defaults to [defaultExternalOnlyFilter].
  ///
  /// [storeInputResponseMessageFilter] filters response messages before
  /// storing context. Defaults to [defaultNoopFilter].
  AIContextProvider({
    Iterable<ChatMessage> Function(Iterable<ChatMessage>)? provideInputMessageFilter,
    Iterable<ChatMessage> Function(Iterable<ChatMessage>)? storeInputRequestMessageFilter,
    Iterable<ChatMessage> Function(Iterable<ChatMessage>)? storeInputResponseMessageFilter,
  })  : provideInputMessageFilter =
            provideInputMessageFilter ?? defaultExternalOnlyFilter,
        storeInputRequestMessageFilter =
            storeInputRequestMessageFilter ?? defaultExternalOnlyFilter,
        storeInputResponseMessageFilter =
            storeInputResponseMessageFilter ?? defaultNoopFilter;

  List<String>? _stateKeys;

  /// Filter applied to input messages before providing context.
  final Iterable<ChatMessage> Function(Iterable<ChatMessage>)
      provideInputMessageFilter;

  /// Filter applied to request messages before storing context.
  final Iterable<ChatMessage> Function(Iterable<ChatMessage>)
      storeInputRequestMessageFilter;

  /// Filter applied to response messages before storing context.
  final Iterable<ChatMessage> Function(Iterable<ChatMessage>)
      storeInputResponseMessageFilter;

  static Iterable<ChatMessage> defaultExternalOnlyFilter(
      Iterable<ChatMessage> messages) {
    return messages.where((m) =>
        m.getAgentRequestMessageSourceType() ==
        AgentRequestMessageSourceType.externalValue);
  }

  static Iterable<ChatMessage> defaultNoopFilter(
          Iterable<ChatMessage> messages) =>
      messages;

  /// The keys used to store provider state in the [StateBag].
  ///
  /// Defaults to a single key equal to the runtime type name.
  List<String> get stateKeys =>
      _stateKeys ??= [runtimeType.toString()];

  /// Called at the start of agent invocation to provide additional context.
  Future<AIContext> invoking(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) {
    return invokingCore(context, cancellationToken: cancellationToken);
  }

  /// Core implementation of [invoking]. Filters messages, calls
  /// [provideAIContext], and merges the returned context with the input.
  Future<AIContext> invokingCore(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final inputContext = context.aiContext;
    final filteredContext = InvokingContext(
      context.agent,
      context.session,
      AIContext()
        ..messages =
            provideInputMessageFilter(inputContext.messages ?? const [])
        ..tools = inputContext.tools
        ..instructions = inputContext.instructions,
    );
    final provided = await provideAIContext(
      filteredContext,
      cancellationToken: cancellationToken,
    );

    final String? mergedInstructions;
    if (inputContext.instructions == null && provided.instructions == null) {
      mergedInstructions = null;
    } else if (provided.instructions == null) {
      mergedInstructions = inputContext.instructions;
    } else if (inputContext.instructions == null) {
      mergedInstructions = provided.instructions;
    } else {
      mergedInstructions =
          '${inputContext.instructions}\n${provided.instructions}';
    }

    final providedMessages = provided.messages?.map((m) =>
        m.withAgentRequestMessageSource(
          AgentRequestMessageSourceType.aiContextProvider,
          sourceId: runtimeType.toString(),
        ));

    final Iterable<ChatMessage>? mergedMessages;
    if (inputContext.messages == null && providedMessages == null) {
      mergedMessages = null;
    } else if (providedMessages == null) {
      mergedMessages = inputContext.messages;
    } else if (inputContext.messages == null) {
      mergedMessages = providedMessages;
    } else {
      mergedMessages = [...inputContext.messages!, ...providedMessages];
    }

    final Iterable<AITool>? mergedTools;
    if (inputContext.tools == null && provided.tools == null) {
      mergedTools = null;
    } else if (provided.tools == null) {
      mergedTools = inputContext.tools;
    } else if (inputContext.tools == null) {
      mergedTools = provided.tools;
    } else {
      mergedTools = [...inputContext.tools!, ...provided.tools!];
    }

    return AIContext()
      ..instructions = mergedInstructions
      ..messages = mergedMessages
      ..tools = mergedTools;
  }

  /// When overridden in a derived class, provides additional AI context to
  /// be merged with the input context for the current invocation.
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) =>
      Future.value(AIContext());

  /// Called at the end of the agent invocation to process results.
  Future<void> invoked(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) {
    return invokedCore(context, cancellationToken: cancellationToken);
  }

  /// Core implementation of [invoked]. Skips processing on failure, applies
  /// message filters, then calls [storeAIContext].
  Future<void> invokedCore(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) {
    if (context.invokeException != null) return Future.value();
    final subContext = InvokedContext(
      context.agent,
      context.session,
      storeInputRequestMessageFilter(context.requestMessages),
      responseMessages:
          storeInputResponseMessageFilter(context.responseMessages ?? const []),
    );
    return storeAIContext(subContext, cancellationToken: cancellationToken);
  }

  /// When overridden in a derived class, processes invocation results.
  Future<void> storeAIContext(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) =>
      Future.value();

  /// Returns a service of the specified [serviceType], or `null`.
  Object? getService(Type serviceType, {Object? serviceKey}) {
    return serviceType == AIContextProvider ? this : null;
  }
}

/// Context passed to [AIContextProvider.invoked].
class InvokedContext {
  InvokedContext(
    this.agent,
    this.session,
    this.requestMessages, {
    Iterable<ChatMessage>? responseMessages,
    this.invokeException,
  }) : responseMessages = responseMessages;

  /// The agent that was invoked.
  final AIAgent agent;

  /// The session associated with the agent invocation.
  final AgentSession? session;

  /// The accumulated request messages used by the agent for this invocation.
  final Iterable<ChatMessage> requestMessages;

  /// The response messages generated during this invocation.
  final Iterable<ChatMessage>? responseMessages;

  /// The exception thrown during the invocation, if any.
  final Exception? invokeException;
}

/// Context passed to [AIContextProvider.invoking].
class InvokingContext {
  InvokingContext(this.agent, this.session, this.aiContext);

  /// The agent being invoked.
  final AIAgent agent;

  /// The session associated with the agent invocation.
  final AgentSession? session;

  /// The [AIContext] being built for the current invocation.
  final AIContext aiContext;
}
