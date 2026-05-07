import '../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'ai_agent_binding.dart';
import 'ai_agent_host_options.dart';
import 'chat_protocol_executor.dart';
import 'executor_binding.dart';
import 'executor_instance_binding.dart';
import 'executor_options.dart';
import 'specialized/ai_agent_host_executor.dart';

/// Extension methods for using [AIAgent] instances in workflows.
extension AIAgentExtensions on AIAgent {
  /// Creates a workflow binding for this agent.
  AIAgentBinding asWorkflowExecutorBinding({
    String? id,
    AgentSession? session,
    AgentRunOptions? runOptions,
    ExecutorOptions? options,
  }) => AIAgentBinding(
    this,
    id: id,
    session: session,
    runOptions: runOptions,
    options: options,
  );

  /// Creates a chat protocol executor for this agent.
  ChatProtocolExecutor asWorkflowExecutor({
    String? id,
    AgentSession? session,
    AgentRunOptions? runOptions,
    ExecutorOptions? options,
  }) => ChatProtocolExecutor(
    this,
    id: id,
    session: session,
    runOptions: runOptions,
    options: options,
  );

  /// Binds this agent as a workflow host executor.
  ExecutorBinding bindAsExecutor([AIAgentHostOptions? options]) =>
      ExecutorInstanceBinding(AIAgentHostExecutor(this, options: options));
}
