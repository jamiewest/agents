import 'package:extensions/system.dart';

import '../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'chat_protocol.dart';
import 'executor.dart';
import 'executor_options.dart';
import 'protocol_builder.dart';
import 'workflow_context.dart';

/// Workflow executor that invokes an [AIAgent] using the chat protocol.
class ChatProtocolExecutor extends Executor<Object?, AgentResponse> {
  /// Creates a chat protocol executor for [agent].
  ChatProtocolExecutor(
    this.agent, {
    String? id,
    this.session,
    this.runOptions,
    ExecutorOptions? options,
  }) : super(id ?? agent.name ?? agent.id, options: options);

  /// Gets the agent invoked by this executor.
  final AIAgent agent;

  /// Gets or sets the reusable agent session.
  AgentSession? session;

  /// Gets the run options supplied to each invocation.
  final AgentRunOptions? runOptions;

  @override
  void configureProtocol(ProtocolBuilder builder) {
    ChatProtocol.configureInput(builder);
    builder.sendsMessage<AgentResponse>();
  }

  @override
  Future<AgentResponse> handle(
    Object? message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final messages = ChatProtocol.toChatMessages(message);
    final effectiveSession = session ??= await agent.createSession(
      cancellationToken: cancellationToken,
    );
    return agent.run(
      effectiveSession,
      runOptions,
      cancellationToken ?? CancellationToken.none,
      messages: messages,
    );
  }
}
