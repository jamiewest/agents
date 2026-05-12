import 'package:extensions/system.dart';

import '../workflow.dart';
import '../workflow_execution_environment.dart';
import '../workflow_output_event.dart';

/// Evaluation helpers for [WorkflowExecutionEnvironment].
extension WorkflowEvaluationExtensions on WorkflowExecutionEnvironment {
  /// Runs [workflow] with [input] and returns the emitted output values.
  ///
  /// Convenience wrapper that extracts [WorkflowOutputEvent.data] values from
  /// the completed run, useful for evaluation pipelines and unit tests.
  Future<List<Object?>> runAndGetOutputsAsync<TInput>(
    Workflow workflow,
    TInput input, {
    String? sessionId,
    CancellationToken? cancellationToken,
  }) async {
    final run = await runAsync<TInput>(
      workflow,
      input,
      sessionId: sessionId,
      cancellationToken: cancellationToken,
    );
    return run.outgoingEvents
        .whereType<WorkflowOutputEvent>()
        .map((event) => event.data)
        .toList();
  }
}
