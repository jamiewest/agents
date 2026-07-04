import 'dart:async';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../abstractions/agent_session.dart';
import '../../abstractions/ai_agent.dart';

/// A delegating chat client that supports injecting messages into the
/// function execution loop.
///
/// This decorator enables external code (such as tool delegates) to enqueue
/// messages that will be sent to the underlying model at the next
/// opportunity. It sits between the [FunctionInvokingChatClient] and the
/// `PerServiceCallChatHistoryPersistingChatClient` (or the leaf [ChatClient])
/// in a `ChatClientAgent` pipeline.
///
/// The injected messages queue is stored per-session in the session's
/// `AgentSessionStateBag`, ensuring isolation between concurrent sessions.
///
/// After each service call, if no function call is returned but injected
/// messages are pending, the decorator loops internally and calls the inner
/// client again with the new messages. When function calls are present,
/// control returns to the parent [FunctionInvokingChatClient] loop.
///
/// This chat client must be used within the context of a running
/// `ChatClientAgent`: it retrieves the current session from
/// [AIAgent.currentRunContext], which is set automatically when an agent's
/// `run` or `runStreaming` method is called.
class MessageInjectingChatClient extends DelegatingChatClient {
  /// Creates the decorator wrapping [innerClient].
  MessageInjectingChatClient(super.innerClient);

  /// The key used to store the pending injected messages queue in the
  /// session's `AgentSessionStateBag`.
  static const String pendingMessagesStateKey =
      'MessageInjectingChatClient.PendingInjectedMessages';

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final session = _getRequiredSession();
    final queue = _getOrCreateQueue(session);

    var newMessages = _drainInjectedMessages(queue, messages.toList());
    var currentOptions = options;

    // Loop to process injected messages: after each service call, if no
    // function calls are pending but new messages have been injected into
    // the queue, call the service again so the model can process them. The
    // loop exits when the response contains function calls (handed off to
    // the parent FunctionInvokingChatClient) or the queue is empty.
    while (true) {
      final response = await super.getResponse(
        messages: newMessages,
        options: currentOptions,
        cancellationToken: cancellationToken,
      );

      if (_hasFunctionCalls(response.messages)) {
        return response;
      }

      if (queue.isEmpty) {
        return response;
      }

      currentOptions = _optionsForNextIteration(
        currentOptions,
        response.conversationId,
      );
      newMessages = _drainInjectedMessages(queue, const <ChatMessage>[]);
    }
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final session = _getRequiredSession();
    final queue = _getOrCreateQueue(session);

    var newMessages = _drainInjectedMessages(queue, messages.toList());
    var currentOptions = options;

    while (true) {
      var hasFunctionCalls = false;
      String? lastConversationId;

      await for (final update in super.getStreamingResponse(
        messages: newMessages,
        options: currentOptions,
        cancellationToken: cancellationToken,
      )) {
        if (!hasFunctionCalls &&
            update.contents.any((content) => content is FunctionCallContent)) {
          hasFunctionCalls = true;
        }
        if (update.conversationId != null) {
          lastConversationId = update.conversationId;
        }
        yield update;
      }

      if (hasFunctionCalls || queue.isEmpty) {
        return;
      }

      currentOptions = _optionsForNextIteration(
        currentOptions,
        lastConversationId,
      );
      newMessages = _drainInjectedMessages(queue, const <ChatMessage>[]);
    }
  }

  /// Enqueues one or more messages to be used at the next opportunity.
  ///
  /// Can be called from tool delegates or other code while the function
  /// execution loop is in progress; the enqueued messages are picked up at
  /// the next opportunity.
  void enqueueMessages(AgentSession session, Iterable<ChatMessage> messages) {
    _getOrCreateQueue(session).addAll(messages);
  }

  /// Gets a point-in-time snapshot of the pending injected messages for the
  /// specified [session] that have not yet been consumed by the injection
  /// loop.
  List<ChatMessage> getPendingMessages(AgentSession session) {
    final (found, queue) = session.stateBag.tryGetValue<List<ChatMessage>>(
      pendingMessagesStateKey,
    );
    if (!found || queue == null || queue.isEmpty) {
      return const <ChatMessage>[];
    }
    return List<ChatMessage>.of(queue);
  }

  /// Gets or creates the pending injected messages queue from the session's
  /// `AgentSessionStateBag`.
  static List<ChatMessage> _getOrCreateQueue(AgentSession session) {
    final (found, queue) = session.stateBag.tryGetValue<List<ChatMessage>>(
      pendingMessagesStateKey,
    );
    if (found && queue != null) {
      return queue;
    }
    final newQueue = <ChatMessage>[];
    session.stateBag.setValue<List<ChatMessage>>(
      pendingMessagesStateKey,
      newQueue,
    );
    return newQueue;
  }

  /// Gets the current [AgentSession] from the run context.
  static AgentSession _getRequiredSession() {
    final runContext = AIAgent.currentRunContext;
    if (runContext == null) {
      throw StateError(
        'MessageInjectingChatClient can only be used within the context of a '
        'running AIAgent. Ensure that the chat client is being invoked as '
        'part of an AIAgent.run or AIAgent.runStreaming call.',
      );
    }
    final session = runContext.session;
    if (session == null) {
      throw StateError(
        'MessageInjectingChatClient requires a session. The current run '
        'context does not have a session.',
      );
    }
    return session;
  }

  /// Drains all pending injected messages from [queue] and returns a new
  /// list combining [newMessages] with the drained messages. The original
  /// list is never modified.
  static List<ChatMessage> _drainInjectedMessages(
    List<ChatMessage> queue,
    List<ChatMessage> newMessages,
  ) {
    if (queue.isEmpty) {
      return newMessages;
    }
    final combined = <ChatMessage>[...newMessages, ...queue];
    queue.clear();
    return combined;
  }

  /// Determines whether any message contains a [FunctionCallContent].
  static bool _hasFunctionCalls(List<ChatMessage> responseMessages) =>
      responseMessages.any(
        (message) =>
            message.contents.any((content) => content is FunctionCallContent),
      );

  /// Propagates [conversationId] from the service response into the options
  /// for the next loop iteration, cloning before mutating to avoid affecting
  /// the caller's instance.
  static ChatOptions? _optionsForNextIteration(
    ChatOptions? options,
    String? conversationId,
  ) {
    if (options == null) {
      return conversationId == null
          ? null
          : (ChatOptions()..conversationId = conversationId);
    }
    if (options.conversationId == conversationId) {
      return options;
    }
    return options.clone()..conversationId = conversationId;
  }
}
