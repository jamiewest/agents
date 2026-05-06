import 'package:extensions/ai.dart';
import '../../func_typedefs.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../ai/microsoft_agents_ai/chat_client/chat_client_agent_options.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import 'ai_agent_host_options.dart';
import 'executor_binding.dart';
import 'group_chat_manager.dart';
import 'group_chat_workflow_builder.dart';
import 'handoff_workflow_builder.dart';
import 'specialized/aggregate_turn_messages_executor.dart';
import 'specialized/concurrent_end_executor.dart';
import 'workflow.dart';

/// Provides utility methods for constructing common patterns of workflows
/// composed of agents.
class AgentWorkflowBuilder {
  AgentWorkflowBuilder();

  /// Builds a [Workflow] composed of a pipeline of agents where the output of
  /// one agent is the input to the next.
  ///
  /// Returns: The built workflow composed of the supplied `agents`, in the
  /// order in which they were yielded from the source.
  ///
  /// [agents] The sequence of agents to compose into a sequential workflow.
  static Workflow buildSequential(Iterable<AIAgent> agents, {String? workflowName, }) {
    return buildSequentialCore(workflowName: null, agents);
  }

  static Workflow buildSequentialCore(String? workflowName, Iterable<AIAgent> agents, ) {
    var options = new()
        {
            ReassignOtherAgentsAsUsers = true,
            ForwardIncomingMessages = true,
        };
    var agentExecutors = agents.map((agent) => agent.bindAsExecutor(options)).toList();
    var previous = agentExecutors[0];
    var builder = new(previous);
    for (final next in agentExecutors.skip(1)) {
      builder.addEdge(previous, next);
      previous = next;
    }
    var end = new();
    builder = builder.addEdge(previous, end).withOutputFrom(end);
    if (workflowName != null) {
      builder = builder.withName(workflowName);
    }
    return builder.build();
  }

  /// Builds a [Workflow] composed of agents that operate concurrently on the
  /// same input, aggregating their outputs into a single collection.
  ///
  /// Returns: The built workflow composed of the supplied concurrent `agents`.
  ///
  /// [agents] The set of agents to compose into a concurrent workflow.
  ///
  /// [aggregator] The aggregation function that accepts a list of the output
  /// messages from each `agents` and produces a single result list. If `null`,
  /// the default behavior is to return a list containing the last message from
  /// each agent that produced at least one message.
  static Workflow buildConcurrent(
    Iterable<AIAgent> agents,
    Func<List<List<ChatMessage>>, List<ChatMessage>>? aggregator,
    {String? workflowName, }
  ) {
    return buildConcurrentCore(workflowName: null, agents, aggregator);
  }

  static Workflow buildConcurrentCore(
    String? workflowName,
    Iterable<AIAgent> agents,
    {Func<List<List<ChatMessage>>, List<ChatMessage>>? aggregator, }
  ) {
    var start = new("Start");
    var builder = new(start);
    var agentExecutors = (from agent in agents
                                            select agent.bindAsExecutor(aiAgentHostOptions())).toList();
    var accumulators = [...from agent in agentExecutors select (ExecutorBinding)aggregateTurnMessagesExecutor('Batcher/${agent.id}')];
    builder.addFanOutEdge(start, agentExecutors);
    for (var i = 0; i < agentExecutors.length; i++) {
      builder.addEdge(agentExecutors[i], accumulators[i]);
    }
    // Create the accumulating executor that will gather the results from each agent, and connect
        // each agent's accumulator to it. If no aggregation function was provided, we default to returning
        // the last message from each agent
        aggregator ??= (lists) => (from list in lists where list.length > 0 select list.last()).toList();
    var endFactory = (_, __) => new(concurrentEndExecutor(agentExecutors.length, aggregator));
    var end = endFactory.bindExecutor(ConcurrentEndExecutor.executorId);
    builder.addFanInBarrierEdge(accumulators, end);
    builder = builder.withOutputFrom(end);
    if (workflowName != null) {
      builder = builder.withName(workflowName);
    }
    return builder.build();
  }

  /// Creates a new [HandoffWorkflowBuilder] using `initialAgent` as the
  /// starting agent in the workflow.
  ///
  /// Remarks: Handoffs between agents are achieved by the current agent
  /// invoking an [AITool] provided to an agent via [ChatClientAgentOptions]'s
  /// [ChatOptions].[Tools]. The [AIAgent] must be capable of understanding
  /// those [AgentRunOptions] provided. If the agent ignores the tools or is
  /// otherwise unable to advertize them to the underlying provider, handoffs
  /// will not occur.
  ///
  /// Returns: The builder for creating a workflow based on handoffs.
  ///
  /// [initialAgent] The agent that will receive inputs provided to the
  /// workflow.
  static HandoffWorkflowBuilder createHandoffBuilderWith(AIAgent initialAgent) {
    return new(initialAgent);
  }

  /// Creates a new [GroupChatWorkflowBuilder] with `managerFactory`.
  ///
  /// Remarks: Handoffs between agents are achieved by the current agent
  /// invoking an [AITool] provided to an agent via [ChatClientAgentOptions]'s
  /// [ChatOptions].[Tools]. The [AIAgent] must be capable of understanding
  /// those [AgentRunOptions] provided. If the agent ignores the tools or is
  /// otherwise unable to advertize them to the underlying provider, handoffs
  /// will not occur.
  ///
  /// Returns: The builder for creating a workflow based on handoffs.
  ///
  /// [managerFactory] Function that will create the [GroupChatManager] for the
  /// workflow instance. The manager will be provided with the set of agents
  /// that will participate in the group chat.
  static GroupChatWorkflowBuilder createGroupChatBuilderWith(Func<List<AIAgent>, GroupChatManager> managerFactory) {
    return groupChatWorkflowBuilder(managerFactory);
  }
}
