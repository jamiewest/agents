import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../../ai/microsoft_agents_ai/chat_client/chat_client_agent_run_options.dart';
import '../chat_protocol.dart';
import '../executor.dart';
import '../handoff_tool_call_filtering_behavior.dart';
import '../handoff_workflow_builder.dart';
import '../protocol_builder.dart';
import '../resettable_executor.dart';
import '../workflow_context.dart';
import 'handoff_agent_executor.dart';
import 'handoff_messages_filter.dart';
import 'handoff_target.dart';

/// Executor used at the start of a handoff workflow.
class HandoffStartExecutor extends Executor<Object?, List<ChatMessage>>
    implements ResettableExecutor {
  /// Creates a [HandoffStartExecutor].
  HandoffStartExecutor({
    required this.initialAgent,
    required Map<String, List<HandoffTarget>> targets,
    this.handoffInstructions,
    this.emitAgentResponseEvents = false,
    this.emitAgentResponseUpdateEvents,
    this.toolCallFilteringBehavior =
        HandoffToolCallFilteringBehavior.handoffOnly,
    this.returnToPrevious = false,
  }) : targets = {
         for (final entry in targets.entries)
           entry.key: List<HandoffTarget>.unmodifiable(entry.value),
       },
       super(executorId);

  /// Gets the executor identifier.
  static const String executorId = 'HandoffStart';

  /// Gets the initial agent.
  final AIAgent initialAgent;

  /// Gets handoff targets by source agent ID.
  final Map<String, List<HandoffTarget>> targets;

  /// Gets instructions supplied when handoff tools are available.
  final String? handoffInstructions;

  /// Gets whether aggregated response events should be emitted.
  final bool emitAgentResponseEvents;

  /// Gets whether streaming update events should be emitted.
  final bool? emitAgentResponseUpdateEvents;

  /// Gets the handoff tool call filtering behavior.
  final HandoffToolCallFilteringBehavior toolCallFilteringBehavior;

  /// Gets whether future turns should return to the previous specialist.
  final bool returnToPrevious;

  final Map<String, AgentSession> _sessions = <String, AgentSession>{};
  String? _previousAgentId;

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
    final history = List<ChatMessage>.of(ChatProtocol.toChatMessages(message));
    var agent = _startingAgent();
    var takingHandoff = false;

    while (true) {
      token.throwIfCancellationRequested();
      final messagesForAgent = takingHandoff
          ? HandoffMessagesFilter(
              toolCallFilteringBehavior,
            ).filterMessages(history).toList()
          : List<ChatMessage>.of(history);
      final response = await _invokeAgent(agent, messagesForAgent, token);
      final responseMessages = _normalizeAuthor(response, agent).toList();
      history.addAll(responseMessages);

      if (emitAgentResponseEvents) {
        await context.yieldOutput(
          AgentResponse(messages: responseMessages),
          cancellationToken: token,
        );
      }

      final request = _findLastHandoffRequest(agent, responseMessages);
      if (request == null) {
        _previousAgentId = agent.id;
        return history;
      }

      history.add(
        ChatMessage(
          role: ChatRole.tool,
          contents: [HandoffAgentExecutor.createHandoffResult(request.callId)],
          authorName: agent.name ?? agent.id,
        ),
      );
      agent = request.target;
      takingHandoff = true;
    }
  }

  AIAgent _startingAgent() {
    if (returnToPrevious && _previousAgentId != null) {
      for (final agent in _allAgents) {
        if (agent.id == _previousAgentId) {
          return agent;
        }
      }
    }
    return initialAgent;
  }

  Iterable<AIAgent> get _allAgents sync* {
    final seen = <String>{};
    if (seen.add(initialAgent.id)) {
      yield initialAgent;
    }
    for (final handoffs in targets.values) {
      for (final handoff in handoffs) {
        if (seen.add(handoff.target.id)) {
          yield handoff.target;
        }
      }
    }
  }

  Future<AgentResponse> _invokeAgent(
    AIAgent agent,
    List<ChatMessage> messages,
    CancellationToken cancellationToken,
  ) async {
    final session = _sessions[agent.id] ??= await agent.createSession(
      cancellationToken: cancellationToken,
    );
    return agent.run(
      session,
      _createAgentOptions(agent),
      cancellationToken: cancellationToken,
      messages: _changeAssistantToUserForOtherParticipants(
        messages,
        agent.name ?? agent.id,
      ),
    );
  }

  ChatClientAgentRunOptions? _createAgentOptions(AIAgent agent) {
    final handoffs = targets[agent.id] ?? const <HandoffTarget>[];
    if (handoffs.isEmpty) {
      return null;
    }

    return ChatClientAgentRunOptions(
      chatOptions: ChatOptions(
        instructions: handoffInstructions,
        allowMultipleToolCalls: false,
        tools: [
          for (var i = 0; i < handoffs.length; i++)
            AIFunctionFactory.create(
              name: '${HandoffWorkflowBuilder.functionPrefix}${i + 1}',
              description: handoffs[i].reason,
              parametersSchema: const <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'reasonForHandoff': <String, dynamic>{
                    'type': 'string',
                    'description': 'The reason for the handoff',
                  },
                },
              },
              callback: (arguments, {cancellationToken}) async => null,
            ),
        ],
      ),
    );
  }

  _HandoffRequest? _findLastHandoffRequest(
    AIAgent source,
    Iterable<ChatMessage> responseMessages,
  ) {
    final handoffs = targets[source.id] ?? const <HandoffTarget>[];
    if (handoffs.isEmpty) {
      return null;
    }
    final byName = <String, HandoffTarget>{
      for (var i = 0; i < handoffs.length; i++)
        '${HandoffWorkflowBuilder.functionPrefix}${i + 1}': handoffs[i],
    };

    _HandoffRequest? last;
    for (final message in responseMessages) {
      for (final content in message.contents) {
        if (content is FunctionCallContent &&
            byName.containsKey(content.name)) {
          last = _HandoffRequest(content.callId, byName[content.name]!.target);
        }
      }
    }
    return last;
  }

  static Iterable<ChatMessage> _normalizeAuthor(
    AgentResponse response,
    AIAgent agent,
  ) sync* {
    for (final message in response.messages) {
      if (message.authorName == null && message.role == ChatRole.assistant) {
        yield ChatMessage(
          role: message.role,
          contents: message.contents,
          authorName: agent.name ?? agent.id,
          createdAt: message.createdAt,
          messageId: message.messageId,
          rawRepresentation: message.rawRepresentation,
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
          rawRepresentation: message.rawRepresentation,
          additionalProperties: message.additionalProperties,
        )
      else
        message,
  ];

  @override
  Future<bool> reset() async {
    _sessions.clear();
    return true;
  }
}

class _HandoffRequest {
  const _HandoffRequest(this.callId, this.target);

  final String callId;
  final AIAgent target;
}
