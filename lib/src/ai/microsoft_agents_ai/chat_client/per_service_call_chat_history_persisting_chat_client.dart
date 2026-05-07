import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'chat_client_agent.dart';
import 'chat_client_agent_session.dart';

/// A sentinel conversation ID used to signal to
/// [FunctionInvokingChatClient] that the conversation is service-managed
/// (for internal bookkeeping only — never sent to the underlying service).
const String localHistoryConversationId =
    '__perServiceCallChatHistoryPersistence__';

/// A delegating chat client that persists chat history and updates session
/// state after each individual service call within the function-invoking loop.
///
/// Activated when [ChatClientAgentOptions.requirePerServiceCallChatHistoryPersistence]
/// is `true`. Operates between [FunctionInvokingChatClient] and the leaf
/// [ChatClient].
class PerServiceCallChatHistoryPersistingChatClient
    extends DelegatingChatClient {
  /// Creates a [PerServiceCallChatHistoryPersistingChatClient] wrapping
  /// [innerClient].
  PerServiceCallChatHistoryPersistingChatClient(super.innerClient);

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final (agent, session) = _getRequiredAgentAndSession();
    options = _stripLocalHistoryConversationId(options);

    final isServiceManaged =
        options?.conversationId != null && options!.conversationId!.isNotEmpty;
    final isContinuationOrBackground =
        options?.continuationToken != null ||
        options?.allowBackgroundResponses == true;
    final skipSimulation = isServiceManaged || isContinuationOrBackground;

    final newMessages = messages is List<ChatMessage>
        ? messages
        : messages.toList();

    final messagesForService = skipSimulation
        ? newMessages
        : await agent.loadChatHistory(
            session,
            newMessages,
            options,
            cancellationToken,
          );

    ChatResponse response;
    try {
      response = await innerClient.getResponse(
        messages: messagesForService,
        options: options,
        cancellationToken: cancellationToken,
      );
    } catch (ex) {
      await agent.notifyProvidersOfFailure(
        session,
        ex is Exception ? ex : Exception(ex.toString()),
        newMessages,
        options,
        cancellationToken,
      );
      rethrow;
    }

    await agent.notifyProvidersOfNewMessages(
      session,
      newMessages,
      response.messages,
      options,
      cancellationToken,
    );

    if (!isContinuationOrBackground) {
      if (isServiceManaged ||
          (response.conversationId != null &&
              response.conversationId!.isNotEmpty)) {
        agent.updateSessionConversationId(
          session,
          response.conversationId,
          cancellationToken,
        );
      } else {
        setSentinelConversationId(response, session);
      }
    }

    return response;
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final (agent, session) = _getRequiredAgentAndSession();
    options = _stripLocalHistoryConversationId(options);

    var isServiceManaged =
        options?.conversationId != null && options!.conversationId!.isNotEmpty;
    final isContinuationOrBackground =
        options?.continuationToken != null ||
        options?.allowBackgroundResponses == true;
    final skipSimulation = isServiceManaged || isContinuationOrBackground;

    final newMessages = messages is List<ChatMessage>
        ? messages
        : messages.toList();

    final Iterable<ChatMessage> messagesForService;
    try {
      messagesForService = skipSimulation
          ? newMessages
          : await agent.loadChatHistory(
              session,
              newMessages,
              options,
              cancellationToken,
            );
    } catch (ex) {
      await agent.notifyProvidersOfFailure(
        session,
        ex is Exception ? ex : Exception(ex.toString()),
        newMessages,
        options,
        cancellationToken,
      );
      rethrow;
    }

    final responseUpdates = <ChatResponseUpdate>[];

    try {
      await for (final update in innerClient.getStreamingResponse(
        messages: messagesForService,
        options: options,
        cancellationToken: cancellationToken,
      )) {
        responseUpdates.add(update.clone());
        if (update.conversationId != null &&
            update.conversationId!.isNotEmpty) {
          isServiceManaged = true;
        } else if (!skipSimulation) {
          update.conversationId = localHistoryConversationId;
        }
        yield update;
      }
    } catch (ex) {
      await agent.notifyProvidersOfFailure(
        session,
        ex is Exception ? ex : Exception(ex.toString()),
        newMessages,
        options,
        cancellationToken,
      );
      rethrow;
    }

    final chatResponse = _buildChatResponse(responseUpdates);

    await agent.notifyProvidersOfNewMessages(
      session,
      newMessages,
      chatResponse.messages,
      options,
      cancellationToken,
    );

    if (!isContinuationOrBackground) {
      if (isServiceManaged) {
        agent.updateSessionConversationId(
          session,
          chatResponse.conversationId,
          cancellationToken,
        );
      } else {
        session.conversationId = localHistoryConversationId;
      }
    }
  }

  /// Sets the sentinel conversation ID on [response] and [session].
  static void setSentinelConversationId(
    ChatResponse response,
    ChatClientAgentSession session,
  ) {
    response.conversationId = localHistoryConversationId;
    session.conversationId = localHistoryConversationId;
  }

  /// Returns the current [ChatClientAgent] and [ChatClientAgentSession] from
  /// the ambient run context.
  ///
  /// Throws [StateError] if called outside an agent run or with an
  /// incompatible agent/session type.
  static (ChatClientAgent, ChatClientAgentSession)
  _getRequiredAgentAndSession() {
    final runContext = AIAgent.currentRunContext;
    if (runContext == null) {
      throw StateError(
        'PerServiceCallChatHistoryPersistingChatClient can only be used '
        'within the context of a running AIAgent.',
      );
    }
    if (runContext.agent is! ChatClientAgent) {
      throw StateError(
        'PerServiceCallChatHistoryPersistingChatClient can only be used with '
        'a ChatClientAgent. Current agent: ${runContext.agent.runtimeType}.',
      );
    }
    if (runContext.session is! ChatClientAgentSession) {
      throw StateError(
        'PerServiceCallChatHistoryPersistingChatClient requires a '
        'ChatClientAgentSession. Current session: '
        '${runContext.session?.runtimeType ?? 'null'}.',
      );
    }
    return (
      runContext.agent as ChatClientAgent,
      runContext.session as ChatClientAgentSession,
    );
  }

  /// Strips the [localHistoryConversationId] sentinel from [options], if
  /// present, to avoid sending it to the inner client.
  static ChatOptions? _stripLocalHistoryConversationId(ChatOptions? options) {
    if (options?.conversationId == localHistoryConversationId) {
      options = options!.clone();
      options.conversationId = null;
    }
    return options;
  }

  static ChatResponse _buildChatResponse(List<ChatResponseUpdate> updates) {
    final messages = <ChatMessage>[];
    ChatMessage? current;
    for (final update in updates) {
      final needsNew =
          current == null ||
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
      current.contents.addAll(update.contents);
    }
    return ChatResponse(
      messages: messages,
      conversationId: updates.lastOrNull?.conversationId,
      finishReason: updates.lastOrNull?.finishReason,
      continuationToken: updates.lastOrNull?.continuationToken,
    );
  }
}
