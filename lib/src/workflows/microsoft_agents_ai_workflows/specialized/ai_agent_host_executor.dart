import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../agent_response_event.dart';
import '../agent_response_update_event.dart';
import '../ai_agent_host_options.dart';
import '../chat_protocol.dart';
import '../executor.dart';
import '../protocol_builder.dart';
import '../resettable_executor.dart';
import '../workflow_context.dart';

/// Hosts an [AIAgent] as a workflow executor.
class AIAgentHostExecutor extends Executor<Object?, List<ChatMessage>>
    implements ResettableExecutor {
  /// Creates an [AIAgentHostExecutor].
  AIAgentHostExecutor(this.agent, {AIAgentHostOptions? options, String? id})
    : hostOptions = options ?? const AIAgentHostOptions(),
      super(id ?? idFor(agent));

  /// Gets the workflow executor ID for [agent].
  static String idFor(AIAgent agent) => agent.name ?? agent.id;

  /// Gets the hosted agent.
  final AIAgent agent;

  /// Gets host options.
  final AIAgentHostOptions hostOptions;

  AgentSession? _session;

  @override
  void configureProtocol(ProtocolBuilder builder) {
    ChatProtocol.configureInput(builder);
    builder.sendsMessage<List<ChatMessage>>();
  }

  @override
  Future<List<ChatMessage>> handle(
    Object? message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    final incomingMessages = ChatProtocol.toChatMessages(message);
    final messagesForAgent = hostOptions.reassignOtherAgentsAsUsers
        ? _changeAssistantToUserForOtherParticipants(
            incomingMessages,
            agent.name ?? agent.id,
          )
        : incomingMessages;

    final emitUpdates = hostOptions.emitAgentUpdateEvents ?? false;
    final response = emitUpdates
        ? await _runStreaming(messagesForAgent, context, token)
        : await _run(messagesForAgent, token);

    if (hostOptions.emitAgentResponseEvents) {
      await context.yieldOutput(
        AgentResponseEvent(executorId: id, response: response),
        cancellationToken: token,
      );
    }

    final forwardableMessages = filterForwardableMessages(
      _normalizeAuthor(response.messages, agent),
    );
    return <ChatMessage>[
      if (hostOptions.forwardIncomingMessages) ...incomingMessages,
      ...forwardableMessages,
    ];
  }

  Future<AgentResponse> _run(
    Iterable<ChatMessage> messages,
    CancellationToken cancellationToken,
  ) async => agent.run(
    await _ensureSession(cancellationToken),
    null,
    cancellationToken,
    messages: messages,
  );

  Future<AgentResponse> _runStreaming(
    Iterable<ChatMessage> messages,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async {
    final updates = <AgentResponseUpdate>[];
    await for (final update in agent.runStreaming(
      await _ensureSession(cancellationToken),
      null,
      cancellationToken,
      messages: messages,
    )) {
      updates.add(update);
      await context.yieldOutput(
        AgentResponseUpdateEvent(executorId: id, update: update),
        cancellationToken: cancellationToken,
      );
    }
    return AgentResponse(
      messages: [
        for (final update in updates)
          ChatMessage(
            role: update.role ?? ChatRole.assistant,
            contents: update.contents,
            authorName: update.authorName ?? agent.name ?? agent.id,
            createdAt: update.createdAt,
            messageId: update.messageId,
            rawRepresentation: update.rawRepresentation,
            additionalProperties: update.additionalProperties,
          ),
      ],
    );
  }

  Future<AgentSession> _ensureSession(
    CancellationToken cancellationToken,
  ) async {
    return _session ??= await agent.createSession(
      cancellationToken: cancellationToken,
    );
  }

  /// Filters response messages to portable conversational content.
  static List<ChatMessage> filterForwardableMessages(
    Iterable<ChatMessage> messages,
  ) {
    final result = <ChatMessage>[];
    for (final message in messages) {
      final contents = message.contents
          .where(_isForwardableContent)
          .toList(growable: false);
      if (contents.isEmpty) {
        continue;
      }
      result.add(
        ChatMessage(
          role: message.role,
          contents: contents,
          authorName: message.authorName,
          createdAt: message.createdAt,
          messageId: message.messageId,
          additionalProperties: message.additionalProperties,
        ),
      );
    }
    return result;
  }

  static bool _isForwardableContent(AIContent content) =>
      content is TextContent ||
      content is DataContent ||
      content is UriContent ||
      content is FunctionCallContent ||
      content is FunctionResultContent ||
      content is ToolApprovalRequestContent ||
      content is ToolApprovalResponseContent ||
      content is ErrorContent;

  static Iterable<ChatMessage> _normalizeAuthor(
    Iterable<ChatMessage> messages,
    AIAgent agent,
  ) sync* {
    for (final message in messages) {
      if (message.authorName == null && message.role == ChatRole.assistant) {
        yield ChatMessage(
          role: message.role,
          contents: message.contents,
          authorName: agent.name ?? agent.id,
          createdAt: message.createdAt,
          messageId: message.messageId,
          additionalProperties: message.additionalProperties,
        );
      } else {
        yield message;
      }
    }
  }

  static List<ChatMessage> _changeAssistantToUserForOtherParticipants(
    Iterable<ChatMessage> messages,
    String targetAgentName,
  ) => [
    for (final message in messages)
      if (message.role == ChatRole.assistant &&
          message.authorName != targetAgentName &&
          message.contents.every(
            (content) =>
                content is TextContent ||
                content is DataContent ||
                content is UriContent ||
                content is UsageContent,
          ))
        ChatMessage(
          role: ChatRole.user,
          contents: message.contents,
          authorName: message.authorName,
          createdAt: message.createdAt,
          messageId: message.messageId,
          additionalProperties: message.additionalProperties,
        )
      else
        message,
  ];

  @override
  Future<bool> reset() async {
    _session = null;
    return true;
  }
}
