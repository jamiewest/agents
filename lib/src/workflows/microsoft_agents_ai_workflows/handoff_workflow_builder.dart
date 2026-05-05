import 'package:extensions/ai.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'executor_binding.dart';
import 'handoff_tool_call_filtering_behavior.dart';
import 'specialized/handoff_state.dart';
import 'specialized/handoff_target.dart';
import 'turn_token.dart';
import 'workflow.dart';
import 'workflow_builder.dart';

class DiagnosticConstants {
  DiagnosticConstants();

}
class HandoffWorkflowBuilder extends HandoffWorkflowBuilderCore<HandoffWorkflowBuilder> {
  const HandoffWorkflowBuilder(AIAgent initialAgent);

}
/// Provides a builder for specifying the handoff relationships between agents
/// and building the resulting workflow.
class HandoffWorkflowBuilderCore<TBuilder> {
  /// Initializes a new instance of the [HandoffsWorkflowBuilder] class with no
  /// handoff relationships.
  ///
  /// [initialAgent] The first agent to be invoked (prior to any handoff).
  HandoffWorkflowBuilderCore(AIAgent initialAgent) : _initialAgent = initialAgent {
    this._allAgents.add(initialAgent);
  }

  final AIAgent _initialAgent;

  final Map<AIAgent, Set<HandoffTarget>> _targets = {};

  final Set<AIAgent> _allAgents = new(AIAgentIDEqualityComparer.Instance);

  late bool _emitAgentResponseEvents;

  late bool _emitAgentResponseUpdateEvents;

  HandoffToolCallFilteringBehavior _toolCallFilteringBehavior = HandoffToolCallFilteringBehavior.HandoffOnly;

  late bool _returnToPrevious;

  /// Gets or sets additional instructions to provide to an agent that has
  /// handoffs ahow and when to perform them.
  ///
  /// Remarks: By default, simple instructions are included. This may be set to
  /// `null` to avoid including any additional instructions, or may be
  /// customized to provide more specific guidance.
  String? handoffInstructions = DefaultHandoffInstructions;

  /// Sets instructions to provide to each agent that has handoffs ahow and
  /// when to perform them.
  ///
  /// Remarks: In the vast majority of cases, the [DefaultHandoffInstructions]
  /// will be sufficient, and there will be no need to customize. If you do
  /// provide alternate instructions, remember to explain the mechanics of the
  /// handoff function tool call, using see [FunctionPrefix] constant.
  ///
  /// [instructions] The instructions to provide, or `null` to restore the
  /// default instructions.
  TBuilder withHandoffInstructions(String? instructions) {
    this.handoffInstructions = instructions ?? DefaultHandoffInstructions;
    return (TBuilder)this;
  }

  /// Sets a value indicating whether agent streaming update events should be
  /// emitted during execution. If `null`, the value will be taken from the
  /// [TurnToken]
  ///
  /// Returns:
  ///
  /// [emitAgentResponseUpdateEvents]
  TBuilder emitAgentResponseUpdateEvents({bool? emitAgentResponseUpdateEvents}) {
    this._emitAgentResponseUpdateEvents = emitAgentResponseUpdateEvents;
    return (TBuilder)this;
  }

  /// Sets a value indicating whether aggregated agent response events should be
  /// emitted during execution.
  ///
  /// Returns:
  ///
  /// [emitAgentResponseEvents]
  TBuilder emitAgentResponseEvents({bool? emitAgentResponseEvents}) {
    this._emitAgentResponseEvents = emitAgentResponseEvents;
    return (TBuilder)this;
  }

  /// Sets the behavior for filtering [FunctionCallContent] and [Tool] contents
  /// from [ChatMessage]s flowing through the handoff workflow. Defaults to
  /// [HandoffOnly].
  ///
  /// [behavior] The filtering behavior to apply.
  TBuilder withToolCallFilteringBehavior(HandoffToolCallFilteringBehavior behavior) {
    this._toolCallFilteringBehavior = behavior;
    return (TBuilder)this;
  }

  /// Configures the workflow so that subsequent user turns route directly back
  /// to the specialist agent that handled the previous turn, rather than always
  /// routing through the initial (coordinator) agent.
  ///
  /// Returns: The updated [HandoffsWorkflowBuilder] instance.
  TBuilder enableReturnToPrevious() {
    this._returnToPrevious = true;
    return (TBuilder)this;
  }

  /// Adds handoff relationships from a source agent to one or more target
  /// agents.
  ///
  /// Remarks: The handoff reason for each target in `to` is derived from that
  /// agent's description or name.
  ///
  /// Returns: The updated [HandoffsWorkflowBuilder] instance.
  ///
  /// [from] The source agent.
  ///
  /// [to] The target agents to add as handoff targets for the source agent.
  TBuilder withHandoffs({AIAgent? from, Iterable<AIAgent>? to, String? handoffReason, }) {
    for (final target in to) {
      if (target == null) {
        throw ArgumentError.notNull("'$1'");
      }
      this.withHandoff(from, target);
    }
    return (TBuilder)this;
  }

  /// Adds a handoff relationship from a source agent to a target agent with a
  /// custom handoff reason.
  ///
  /// Returns: The updated [HandoffsWorkflowBuilder] instance.
  ///
  /// [from] The source agent.
  ///
  /// [to] The target agent.
  ///
  /// [handoffReason] The reason the `from` should hand off to the `to`. If
  /// `null`, the reason is derived from `to`'s description or name.
  TBuilder withHandoff(AIAgent from, AIAgent to, {String? handoffReason, }) {
    this._allAgents.add(from);
    this._allAgents.add(to);
    var handoffs;
    if (!this._targets.containsKey(from)) {
      this._targets[from] = handoffs = [];
    }
    if ((handoffReason == null || handoffReason.trim().isEmpty)) {
      handoffReason = ((to.description == null || to.description.trim().isEmpty) ? null : to.description)
                         ?? ((to.name == null || to.name.trim().isEmpty) ? null : 'handoff to ${to.name}')
                         ?? to.getService<ChatClientAgent>()?.instructions;
      if ((handoffReason == null || handoffReason.trim().isEmpty)) {
        throw ArgumentError(
          'The provided target agent "${to.name ?? to.id}" has no description, '
          'name, or instructions, and no handoff description has been provided. '
          'At least one of these is required to register a handoff so that the '
          'appropriate target agent can be chosen.',
          'to',
        );
      }
    }
    if (!handoffs.add(HandoffEntry(to, handoffReason))) {
      throw StateError('A handoff from agent "${from.name ?? from.id}" to agent "${to.name ?? to.id}" has already been registered.');
    }
    return (TBuilder)this;
  }

  Map<String, ExecutorBinding> createExecutorBindings(WorkflowBuilder builder) {
    var options = new(this.handoffInstructions,
                                                  this._emitAgentResponseEvents,
                                                  this._emitAgentResponseUpdateEvents,
                                                  this._toolCallFilteringBehavior);
    return this._allAgents.toDictionary(
      keySelector: (a) => a.id,
      elementSelector: CreateFactoryBinding,
    );
    /* TODO: unsupported node kind "unknown" */
    // ExecutorBinding CreateFactoryBinding(AIAgent agent)
    //         {
      //             if (!this._targets.TryGetValue(agent, handoffs))
      //             {
        //                 handoffs = new();
        //             }
      //
      //             // Use the ExecutorId as the placeholder id for a (possibly) future-bound factory
      //             builder.AddSwitch(HandoffAgentExecutor.IdFor(agent), (SwitchBuilder sb) =>
      //             {
        //                 foreach (HandoffTarget handoff in handoffs)
        //                 {
          //                     sb.AddCase<HandoffState>(state => state?.RequestedHandoffTargetAgentId == handoff.Target.Id, // Use AgentId for target matching
          //                                              HandoffAgentExecutor.IdFor(handoff.Target)); // Use ExecutorId in for routing at the workflow level
          //                 }
        //
        //                 sb.WithDefault(HandoffEndExecutor.ExecutorId);
        //             });
      //
      //             ExecutorFactoryFunc factory =
      //                 (config, sessionId) => new(
      //                     new HandoffAgentExecutor(agent,
      //                                              handoffs,
      //                                              options));
      //
      //             // Make sure to use ExecutorId when binding the executor, not AgentId
      //             ExecutorBinding binding = factory.BindExecutor(HandoffAgentExecutor.IdFor(agent));
      //
      //             builder.BindExecutor(binding);
      //
      //             return binding;
      //         }
  }

  /// Builds a [Workflow] composed of agents that operate via handoffs, with the
  /// next agent to process messages selected by the current agent.
  ///
  /// Returns: The workflow built based on the handoffs in the builder.
  Workflow build() {
    var start = new(this._returnToPrevious);
    var end = new(this._returnToPrevious);
    var builder = new(start);
    var executors = this.createExecutorBindings(builder);
    if (this._returnToPrevious) {
      var initialAgentId = this._initialAgent.id;
      builder.addSwitch(start, (sb) =>
            {
                foreach (var agent in this._allAgents)
                {
                    if (agent.id != initialAgentId)
                    {
                        String agentId = agent.id;
                        sb.addCase<HandoffState>(
                          (state) => state?.previousAgentId == agentId,
                          executors[agentId],
                        );
          }
        }

                sb.withDefault(executors[initialAgentId]);
            });
    } else {
      builder.addEdge(start, executors[this._initialAgent.id]);
    }
    return builder.withOutputFrom(end).build();
  }
}
class HandoffsWorkflowBuilder extends HandoffWorkflowBuilderCore<HandoffsWorkflowBuilder> {
  const HandoffsWorkflowBuilder(AIAgent initialAgent);

}
