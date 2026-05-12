import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../chat_protocol.dart';
import '../executor.dart';
import '../protocol_builder.dart';
import '../resettable_executor.dart';
import '../workflow_context.dart';
import '../group_chat_manager.dart';

/// Hosts a group chat workflow and selects participating agents with a manager.
class GroupChatHost extends Executor<Object?, List<ChatMessage>>
    implements ResettableExecutor {
  /// Creates a [GroupChatHost].
  GroupChatHost(super.id, Iterable<AIAgent> agents, this.managerFactory)
    : agents = List<AIAgent>.of(agents);

  /// Gets the participating agents.
  final List<AIAgent> agents;

  /// Gets the manager factory.
  final GroupChatManager Function(List<AIAgent> agents) managerFactory;

  GroupChatManager? _manager;
  final Map<String, AgentSession> _sessions = <String, AgentSession>{};

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
    final manager = _manager ??= managerFactory(
      List<AIAgent>.unmodifiable(agents),
    );
    final history = List<ChatMessage>.of(ChatProtocol.toChatMessages(message));

    while (!await manager.shouldTerminate(history, cancellationToken: token)) {
      final filtered = await manager.updateHistory(
        List<ChatMessage>.unmodifiable(history),
        cancellationToken: token,
      );
      final nextAgent = await manager.selectNextAgent(
        List<ChatMessage>.unmodifiable(history),
        cancellationToken: token,
      );
      if (!agents.any((agent) => agent.id == nextAgent.id)) {
        throw StateError(
          'The group chat manager selected an agent that is not a participant.',
        );
      }

      manager.iterationCount++;
      final session = await _sessionFor(nextAgent, token);
      final response = await nextAgent.run(
        session,
        null,
        cancellationToken: token,
        messages: List<ChatMessage>.of(filtered),
      );
      history.addAll(_normalizeAuthor(response, nextAgent));
    }

    manager.reset();
    _manager = null;
    return history;
  }

  Future<AgentSession> _sessionFor(
    AIAgent agent,
    CancellationToken cancellationToken,
  ) async => _sessions[agent.id] ??= await agent.createSession(
    cancellationToken: cancellationToken,
  );

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

  @override
  Future<bool> reset() async {
    _manager?.reset();
    _manager = null;
    _sessions.clear();
    return true;
  }
}
