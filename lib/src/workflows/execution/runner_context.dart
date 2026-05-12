import '../executor.dart';
import '../workflow.dart';
import '../workflow_event.dart';
import 'edge_map.dart';
import 'message_envelope.dart';
import 'runner_state_data.dart';

/// Shared context for an in-process workflow runner.
class RunnerContext {
  /// Creates runner context.
  RunnerContext({
    required this.workflow,
    required this.executors,
    required this.edgeMap,
    required Iterable<String> outputExecutorIds,
  }) : outputExecutorIds = Set<String>.unmodifiable(outputExecutorIds);

  /// Gets the workflow being executed.
  final Workflow workflow;

  /// Gets executor instances by ID.
  final Map<String, Executor<dynamic, dynamic>> executors;

  /// Gets workflow edges indexed for routing.
  final EdgeMap edgeMap;

  /// Gets output executor IDs.
  final Set<String> outputExecutorIds;

  /// Gets mutable runner state.
  final RunnerStateData state = RunnerStateData();

  /// Gets emitted workflow events.
  final List<WorkflowEvent> events = <WorkflowEvent>[];

  /// Gets whether [executorId] is a workflow output executor.
  bool isOutputExecutor(String executorId) =>
      outputExecutorIds.contains(executorId);

  /// Adds [event] to the emitted events.
  void addEvent(WorkflowEvent event) => events.add(event);

  /// Creates the initial message envelope.
  MessageEnvelope createInitialEnvelope(Object? input) => MessageEnvelope(
    targetExecutorId: workflow.startExecutorId,
    message: input,
  );
}
