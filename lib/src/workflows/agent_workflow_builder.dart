import 'package:extensions/ai.dart';

import '../abstractions/ai_agent.dart';
import 'ai_agent_host_options.dart';
import 'executor_instance_binding.dart';
import 'function_executor.dart';
import 'group_chat_manager.dart';
import 'group_chat_workflow_builder.dart';
import 'handoff_workflow_builder.dart';
import 'specialized/aggregate_turn_messages_executor.dart';
import 'specialized/ai_agent_host_executor.dart';
import 'specialized/concurrent_end_executor.dart';
import 'specialized/output_messages_executor.dart';
import 'workflow.dart';
import 'workflow_builder.dart';
import 'workflow_builder_extensions.dart';

/// Provides utility methods for constructing common agent workflows.
class AgentWorkflowBuilder {
  const AgentWorkflowBuilder._();

  /// Builds a workflow composed of a pipeline of agents.
  static Workflow buildSequential(
    Iterable<AIAgent> agents, {
    String? workflowName,
  }) {
    final agentList = List<AIAgent>.of(agents);
    if (agentList.isEmpty) {
      throw ArgumentError.value(agents, 'agents', 'Agents cannot be empty.');
    }

    final options = const AIAgentHostOptions(
      reassignOtherAgentsAsUsers: true,
      forwardIncomingMessages: true,
    );
    final agentExecutors = [
      for (final agent in agentList)
        AIAgentHostExecutor(agent, options: options),
    ];

    final builder = WorkflowBuilder(ExecutorInstanceBinding(agentExecutors[0]));
    for (final executor in agentExecutors.skip(1)) {
      builder.bindExecutor(executor);
    }

    var previousId = agentExecutors[0].id;
    for (final executor in agentExecutors.skip(1)) {
      builder.addEdge(previousId, executor.id);
      previousId = executor.id;
    }

    final end = OutputMessagesExecutor();
    builder.bindExecutor(end).addEdge(previousId, end.id).addOutput(end.id);
    if (workflowName != null) {
      builder.withName(workflowName);
    }
    return builder.build();
  }

  /// Builds a workflow composed of agents that operate concurrently.
  static Workflow buildConcurrent(
    Iterable<AIAgent> agents, {
    String? workflowName,
    List<ChatMessage> Function(List<List<ChatMessage>> lists)? aggregator,
  }) {
    final agentList = List<AIAgent>.of(agents);
    if (agentList.isEmpty) {
      throw ArgumentError.value(agents, 'agents', 'Agents cannot be empty.');
    }

    final start = FunctionExecutor<List<ChatMessage>, List<ChatMessage>>(
      'Start',
      (input, context, cancellationToken) => input,
    );
    final builder = WorkflowBuilder(ExecutorInstanceBinding(start));

    final agentExecutors = [
      for (final agent in agentList)
        AIAgentHostExecutor(
          agent,
          options: const AIAgentHostOptions(
            reassignOtherAgentsAsUsers: true,
            forwardIncomingMessages: false,
          ),
        ),
    ];
    final batchers = [
      for (final executor in agentExecutors)
        AggregateTurnMessagesExecutor('Batcher/${executor.id}'),
    ];

    for (final executor in agentExecutors) {
      builder.bindExecutor(executor);
    }
    for (final batcher in batchers) {
      builder.bindExecutor(batcher);
    }

    builder.addFanOutEdge(start.id, [
      for (final executor in agentExecutors) executor.id,
    ]);
    for (var i = 0; i < agentExecutors.length; i++) {
      builder.addEdge(agentExecutors[i].id, batchers[i].id);
    }

    final end = ConcurrentEndExecutor(
      agentExecutors.length,
      aggregator ?? _defaultConcurrentAggregator,
    );
    builder.bindExecutor(end);
    builder.addFanInEdge([for (final batcher in batchers) batcher.id], end.id);
    builder.addOutput(end.id);
    if (workflowName != null) {
      builder.withName(workflowName);
    }
    return builder.build();
  }

  /// Creates a new [HandoffWorkflowBuilder] with [initialAgent].
  static HandoffWorkflowBuilder createHandoffBuilderWith(
    AIAgent initialAgent,
  ) => HandoffWorkflowBuilder(initialAgent);

  /// Creates a new [GroupChatWorkflowBuilder] with [managerFactory].
  static GroupChatWorkflowBuilder createGroupChatBuilderWith(
    GroupChatManager Function(List<AIAgent> agents) managerFactory,
  ) => GroupChatWorkflowBuilder(managerFactory);

  static List<ChatMessage> _defaultConcurrentAggregator(
    List<List<ChatMessage>> lists,
  ) => [
    for (final list in lists)
      if (list.isNotEmpty) list.last,
  ];
}
