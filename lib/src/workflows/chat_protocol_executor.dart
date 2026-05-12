import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../abstractions/agent_response.dart';
import '../abstractions/agent_run_options.dart';
import '../abstractions/agent_session.dart';
import '../abstractions/ai_agent.dart';
import 'chat_protocol.dart';
import 'executor.dart';
import 'executor_options.dart';
import 'protocol_builder.dart';
import 'workflow_context.dart';

/// Configuration for [ChatProtocolExecutor].
final class ChatProtocolExecutorOptions {
  /// Creates [ChatProtocolExecutorOptions].
  const ChatProtocolExecutorOptions({
    this.stringMessageChatRole = ChatRole.user,
    this.autoSendTurnToken = false,
  });

  /// The [ChatRole] assigned when wrapping a bare [String] input message.
  final ChatRole stringMessageChatRole;

  /// Whether to append a turn-end token after each invocation.
  final bool autoSendTurnToken;
}

/// Workflow executor that invokes an [AIAgent] using the chat protocol.
class ChatProtocolExecutor extends Executor<Object?, AgentResponse> {
  /// Creates a chat protocol executor for [agent].
  ChatProtocolExecutor(
    this.agent, {
    String? id,
    this.session,
    this.runOptions,
    this.executorOptions = const ChatProtocolExecutorOptions(),
    ExecutorOptions? options,
  }) : super(id ?? agent.name ?? agent.id, options: options);

  /// Gets the agent invoked by this executor.
  final AIAgent agent;

  /// Gets or sets the reusable agent session.
  AgentSession? session;

  /// Gets the run options supplied to each invocation.
  final AgentRunOptions? runOptions;

  /// Gets the chat protocol executor options.
  final ChatProtocolExecutorOptions executorOptions;

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
    final messages = ChatProtocol.toChatMessages(
      message,
      stringRole: executorOptions.stringMessageChatRole,
    );
    final effectiveSession = session ??= await agent.createSession(
      cancellationToken: cancellationToken,
    );
    return agent.run(
      effectiveSession,
      runOptions,
      cancellationToken: cancellationToken,
      messages: messages,
    );
  }
}
