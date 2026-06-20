import '../abstractions/ai_agent.dart';
import 'executor_instance_binding.dart';
import 'magentic_plan_review_request.dart';
import 'magentic_plan_review_response.dart';
import 'request_port.dart';
import 'specialized/magentic/magentic_orchestrator.dart';
import 'specialized/magentic/magentic_task_context.dart';
import 'workflow.dart';
import 'workflow_builder.dart';

/// Fluent builder for Magentic One multi-agent orchestration workflows.
///
/// Magentic workflows use an LLM-powered manager to coordinate a team of agents
/// through dynamic planning, progress tracking, and adaptive replanning. The
/// manager creates plans, selects agents, monitors progress, and decides when
/// to replan or finish.
///
/// When [requirePlanSignoff] is enabled (the default), the workflow pauses for
/// human review of each plan via an external request port; supply a
/// [MagenticPlanReviewResponse] to approve or revise.
class MagenticWorkflowBuilder {
  /// Creates a builder coordinated by [managerAgent].
  MagenticWorkflowBuilder(this.managerAgent);

  /// Identifier of the plan-review request port.
  static const String planReviewPortId = 'RequestPlanReview';

  /// The manager agent that plans and coordinates the team.
  final AIAgent managerAgent;

  final List<AIAgent> _team = <AIAgent>[];
  int _maxStalls = TaskLimits.defaultMaxStallCount;
  int? _maxRounds;
  int? _maxResets;
  bool _requirePlanSignoff = true;
  String? _name;
  String? _description;

  /// Adds the given [agents] as participants.
  MagenticWorkflowBuilder addParticipants(Iterable<AIAgent> agents) {
    _team.addAll(agents);
    return this;
  }

  /// Sets the maximum number of coordination rounds (`null` = unlimited).
  MagenticWorkflowBuilder withMaxRounds([int? maxRounds]) {
    _maxRounds = maxRounds;
    return this;
  }

  /// Sets the maximum number of resets allowed (`null` = unlimited).
  MagenticWorkflowBuilder withMaxResets([int? maxResets]) {
    _maxResets = maxResets;
    return this;
  }

  /// Sets the maximum consecutive stalls before replanning (default 3).
  MagenticWorkflowBuilder withMaxStalls([
    int maxStalls = TaskLimits.defaultMaxStallCount,
  ]) {
    _maxStalls = maxStalls;
    return this;
  }

  /// Sets whether human approval of plans is required before proceeding.
  MagenticWorkflowBuilder requirePlanSignoff([bool requirePlanSignoff = true]) {
    _requirePlanSignoff = requirePlanSignoff;
    return this;
  }

  /// Sets the workflow name.
  MagenticWorkflowBuilder withName(String name) {
    _name = name;
    return this;
  }

  /// Sets the workflow description.
  MagenticWorkflowBuilder withDescription(String description) {
    _description = description;
    return this;
  }

  /// Builds the Magentic [Workflow].
  Workflow build() {
    if (_team.isEmpty) {
      throw StateError(
        'At least one participant must be added via addParticipants() before '
        'building the workflow.',
      );
    }

    // Copy the team so later builder mutations cannot affect the workflow.
    final team = List<AIAgent>.of(_team);
    const port =
        RequestPort<MagenticPlanReviewRequest, MagenticPlanReviewResponse?>(
          planReviewPortId,
        );

    final orchestrator = MagenticOrchestrator(
      managerAgent: managerAgent,
      team: team,
      limits: TaskLimits(
        maxStallCount: _maxStalls,
        maxRoundCount: _maxRounds,
        maxResetCount: _maxResets,
      ),
      requirePlanSignoff: _requirePlanSignoff,
      planReviewPort: port,
    );

    return WorkflowBuilder(ExecutorInstanceBinding(orchestrator))
        .withName(_name)
        .withDescription(_description)
        .addOutput(orchestrator.id)
        .addRequestPort(port.toDescriptor())
        .build();
  }
}
