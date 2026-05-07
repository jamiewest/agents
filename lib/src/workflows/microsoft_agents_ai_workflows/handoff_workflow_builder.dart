import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'executor_instance_binding.dart';
import 'handoff_tool_call_filtering_behavior.dart';
import 'specialized/handoff_start_executor.dart';
import 'specialized/handoff_target.dart';
import 'workflow.dart';
import 'workflow_builder.dart';

/// Provides a builder for specifying handoff relationships between agents.
class HandoffWorkflowBuilder {
  /// Creates a [HandoffWorkflowBuilder].
  HandoffWorkflowBuilder(AIAgent initialAgent) : _initialAgent = initialAgent {
    _allAgents[initialAgent.id] = initialAgent;
  }

  /// The prefix for function calls that trigger handoffs to other agents.
  static const String functionPrefix = 'handoff_to_';

  /// Default instructions for agents that have handoff tools.
  static const String defaultHandoffInstructions =
      '''
You are one agent in a multi-agent system. You can hand off the conversation to another agent if appropriate. Handoffs are achieved
by calling a handoff function, named in the form `$functionPrefix<agent_id>`; the description of the function provides details on the
target agent of that handoff. Handoffs between agents are handled seamlessly in the background; never mention or narrate these handoffs
in your conversation with the user.
''';

  final AIAgent _initialAgent;
  final Map<String, AIAgent> _allAgents = <String, AIAgent>{};
  final Map<String, List<HandoffTarget>> _targets =
      <String, List<HandoffTarget>>{};

  bool _emitAgentResponseEvents = false;
  bool? _emitAgentResponseUpdateEvents;
  HandoffToolCallFilteringBehavior _toolCallFilteringBehavior =
      HandoffToolCallFilteringBehavior.handoffOnly;
  bool _returnToPrevious = false;

  /// Gets or sets additional instructions to provide to agents with handoffs.
  String? handoffInstructions = defaultHandoffInstructions;

  /// Sets instructions to provide to each agent that has handoffs.
  HandoffWorkflowBuilder withHandoffInstructions(String? instructions) {
    handoffInstructions = instructions ?? defaultHandoffInstructions;
    return this;
  }

  /// Sets whether agent streaming update events should be emitted.
  HandoffWorkflowBuilder emitAgentResponseUpdateEvents([
    bool emitAgentResponseUpdateEvents = true,
  ]) {
    _emitAgentResponseUpdateEvents = emitAgentResponseUpdateEvents;
    return this;
  }

  /// Sets whether aggregated agent response events should be emitted.
  HandoffWorkflowBuilder emitAgentResponseEvents([
    bool emitAgentResponseEvents = true,
  ]) {
    _emitAgentResponseEvents = emitAgentResponseEvents;
    return this;
  }

  /// Sets behavior for filtering tool calls from handoff workflow history.
  HandoffWorkflowBuilder withToolCallFilteringBehavior(
    HandoffToolCallFilteringBehavior behavior,
  ) {
    _toolCallFilteringBehavior = behavior;
    return this;
  }

  /// Routes subsequent turns directly back to the previous specialist.
  HandoffWorkflowBuilder enableReturnToPrevious() {
    _returnToPrevious = true;
    return this;
  }

  /// Adds handoff relationships from [from] to [to].
  HandoffWorkflowBuilder withHandoffs(AIAgent from, Iterable<AIAgent> to) {
    for (final target in to) {
      withHandoff(from, target);
    }
    return this;
  }

  /// Adds handoff relationships from [from] sources to [to].
  HandoffWorkflowBuilder withHandoffsTo(
    Iterable<AIAgent> from,
    AIAgent to, {
    String? handoffReason,
  }) {
    for (final source in from) {
      withHandoff(source, to, handoffReason: handoffReason);
    }
    return this;
  }

  /// Adds a handoff relationship from [from] to [to].
  HandoffWorkflowBuilder withHandoff(
    AIAgent from,
    AIAgent to, {
    String? handoffReason,
  }) {
    _allAgents[from.id] = from;
    _allAgents[to.id] = to;

    final reason = _resolveReason(to, handoffReason);
    final handoff = HandoffTarget(to, reason);
    final targets = _targets.putIfAbsent(from.id, () => <HandoffTarget>[]);
    if (targets.contains(handoff)) {
      throw StateError(
        "A handoff from agent '${from.name ?? from.id}' to agent "
        "'${to.name ?? to.id}' has already been registered.",
      );
    }

    targets.add(handoff);
    return this;
  }

  /// Builds the handoff workflow.
  Workflow build() {
    final start = HandoffStartExecutor(
      initialAgent: _initialAgent,
      targets: _targets,
      handoffInstructions: handoffInstructions,
      emitAgentResponseEvents: _emitAgentResponseEvents,
      emitAgentResponseUpdateEvents: _emitAgentResponseUpdateEvents,
      toolCallFilteringBehavior: _toolCallFilteringBehavior,
      returnToPrevious: _returnToPrevious,
    );
    return WorkflowBuilder(
      ExecutorInstanceBinding(start),
    ).addOutput(start.id).build();
  }

  String _resolveReason(AIAgent to, String? handoffReason) {
    var reason = handoffReason;
    if (reason == null || reason.trim().isEmpty) {
      reason = (to.description != null && to.description!.trim().isNotEmpty)
          ? to.description
          : null;
      reason ??= (to.name != null && to.name!.trim().isNotEmpty)
          ? 'handoff to ${to.name}'
          : null;
    }
    if (reason == null || reason.trim().isEmpty) {
      throw ArgumentError.value(
        to,
        'to',
        'The target agent has no description, name, or handoff reason.',
      );
    }
    return reason;
  }
}
