import 'package:extensions/ai.dart';

import '../abstractions/ai_agent.dart';
import 'ai_agent_host_options.dart';
import 'executor_instance_binding.dart';
import 'function_executor.dart';
import 'orchestration_builder_base.dart';
import 'specialized/aggregate_turn_messages_executor.dart';
import 'specialized/ai_agent_host_executor.dart';
import 'specialized/concurrent_end_executor.dart';
import 'workflow.dart';
import 'workflow_builder.dart';
import 'workflow_builder_extensions.dart';

/// Fluent builder for concurrent agent workflows: a fan-out start that
/// broadcasts the incoming messages to every participating agent, a per-agent
/// accumulator that batches each agent's outgoing messages, and a fan-in
/// aggregator that reduces them into a single output list.
///
/// When no explicit output designations are made, the default is the
/// Python-aligned shape: the terminal aggregator is the workflow output, and
/// every participating agent (plus its per-agent accumulator) is designated
/// as an intermediate output source. Calling [withOutputFrom] or
/// [withIntermediateOutputFrom] at all suppresses these defaults.
final class ConcurrentWorkflowBuilder
    extends OrchestrationBuilderBase<ConcurrentWorkflowBuilder> {
  /// Creates a [ConcurrentWorkflowBuilder] with the given participating
  /// [agents].
  ConcurrentWorkflowBuilder(Iterable<AIAgent> agents)
    : _agents = List<AIAgent>.of(agents);

  final List<AIAgent> _agents;
  List<ChatMessage> Function(List<List<ChatMessage>> lists)? _aggregator;

  /// Sets the aggregator function. If not called, defaults to returning the
  /// last message from each agent that produced at least one message.
  ConcurrentWorkflowBuilder withAggregator(
    List<ChatMessage> Function(List<List<ChatMessage>> lists) aggregator,
  ) {
    _aggregator = aggregator;
    return this;
  }

  /// Builds the configured concurrent workflow.
  Workflow build() {
    if (_agents.isEmpty) {
      throw ArgumentError.value(
        _agents,
        'agents',
        'At least one agent must be provided to the '
            'ConcurrentWorkflowBuilder.',
      );
    }

    final start = FunctionExecutor<List<ChatMessage>, List<ChatMessage>>(
      'Start',
      (input, context, cancellationToken) => input,
    );
    final builder = WorkflowBuilder(ExecutorInstanceBinding(start));

    const options = AIAgentHostOptions(
      reassignOtherAgentsAsUsers: true,
      forwardIncomingMessages: false,
    );
    final agentExecutorIds = <String, String>{};
    final agentExecutors = <AIAgentHostExecutor>[];
    final accumulators = <AggregateTurnMessagesExecutor>[];
    for (final agent in _agents) {
      final executor = AIAgentHostExecutor(agent, options: options);
      agentExecutors.add(executor);
      agentExecutorIds[agent.id] = executor.id;
      accumulators.add(AggregateTurnMessagesExecutor('Batcher/${executor.id}'));
    }

    for (final executor in agentExecutors) {
      builder.bindExecutor(executor);
    }
    for (final accumulator in accumulators) {
      builder.bindExecutor(accumulator);
    }

    builder.addFanOutEdge(start.id, [
      for (final executor in agentExecutors) executor.id,
    ]);
    for (var i = 0; i < agentExecutors.length; i++) {
      builder.addEdge(agentExecutors[i].id, accumulators[i].id);
    }

    final end = ConcurrentEndExecutor(
      agentExecutors.length,
      _aggregator ?? _defaultAggregator,
    );
    builder.bindExecutor(end);
    builder.addFanInEdge([
      for (final accumulator in accumulators) accumulator.id,
    ], end.id);

    applyMetadata(builder);
    applyOutputDesignations(builder, agentExecutorIds, 'concurrent', () {
      builder
        ..withOutputFrom([end.id])
        ..withIntermediateOutputFrom([
          for (final executor in agentExecutors) executor.id,
          for (final accumulator in accumulators) accumulator.id,
        ]);
    });

    return builder.build();
  }

  static List<ChatMessage> _defaultAggregator(List<List<ChatMessage>> lists) =>
      [
        for (final list in lists)
          if (list.isNotEmpty) list.last,
      ];
}
