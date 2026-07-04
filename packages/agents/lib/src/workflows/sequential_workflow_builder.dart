import '../abstractions/ai_agent.dart';
import 'ai_agent_host_options.dart';
import 'executor_instance_binding.dart';
import 'orchestration_builder_base.dart';
import 'specialized/ai_agent_host_executor.dart';
import 'specialized/output_messages_executor.dart';
import 'workflow.dart';
import 'workflow_builder.dart';
import 'workflow_builder_extensions.dart';

/// Fluent builder for sequential agent workflows: a pipeline where the output
/// of one agent is the input to the next, terminating in an aggregator that
/// yields the accumulated `ChatMessage`s as the workflow output.
///
/// When no explicit output designations are made, the default is the
/// Python-aligned shape: the terminal aggregator is the workflow output, and
/// every participating agent is designated as an intermediate output source.
/// Calling [withOutputFrom] or [withIntermediateOutputFrom] at all suppresses
/// these defaults.
final class SequentialWorkflowBuilder
    extends OrchestrationBuilderBase<SequentialWorkflowBuilder> {
  /// Creates a [SequentialWorkflowBuilder] with the given pipeline of
  /// [agents].
  SequentialWorkflowBuilder(Iterable<AIAgent> agents)
    : _agents = List<AIAgent>.of(agents);

  final List<AIAgent> _agents;
  bool _chainOnlyAgentResponses = false;

  /// Configures whether each downstream agent should receive only the
  /// previous agent's output, instead of the full accumulated conversation.
  ///
  /// When [enabled], the workflow's terminal output also contains only the
  /// final agent's messages, because incoming messages are no longer
  /// forwarded to the terminal [OutputMessagesExecutor].
  SequentialWorkflowBuilder withChainOnlyAgentResponses({bool enabled = true}) {
    _chainOnlyAgentResponses = enabled;
    return this;
  }

  /// Builds the configured sequential workflow.
  Workflow build() {
    if (_agents.isEmpty) {
      throw ArgumentError.value(
        _agents,
        'agents',
        'At least one agent must be provided to the '
            'SequentialWorkflowBuilder.',
      );
    }

    final options = AIAgentHostOptions(
      reassignOtherAgentsAsUsers: true,
      forwardIncomingMessages: !_chainOnlyAgentResponses,
    );

    final agentExecutorIds = <String, String>{};
    final agentExecutors = <AIAgentHostExecutor>[];
    for (final agent in _agents) {
      final executor = AIAgentHostExecutor(agent, options: options);
      agentExecutors.add(executor);
      agentExecutorIds[agent.id] = executor.id;
    }

    final builder = WorkflowBuilder(ExecutorInstanceBinding(agentExecutors[0]));
    var previousId = agentExecutors[0].id;
    for (final executor in agentExecutors.skip(1)) {
      builder.bindExecutor(executor).addEdge(previousId, executor.id);
      previousId = executor.id;
    }

    final end = OutputMessagesExecutor();
    builder.bindExecutor(end).addEdge(previousId, end.id);

    applyMetadata(builder);
    applyOutputDesignations(builder, agentExecutorIds, 'sequential', () {
      builder
        ..withOutputFrom([end.id])
        ..withIntermediateOutputFrom([
          for (final executor in agentExecutors) executor.id,
        ]);
    });

    return builder.build();
  }
}
