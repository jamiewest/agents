import '../checkpoint_info.dart';
import '../execution/step_tracer.dart';
import '../super_step_completed_event.dart';
import '../super_step_completion_info.dart';
import '../super_step_start_info.dart';
import '../super_step_started_event.dart';

/// [IStepTracer] implementation for in-process workflow execution.
///
/// Tracks instantiated/activated executor IDs per superstep, the current step
/// number, and state/checkpoint events.
final class InProcStepTracer implements IStepTracer {
  int _nextStepNumber = 0;

  /// Gets the step number of the most recently started superstep.
  int get stepNumber => _nextStepNumber - 1;

  /// Gets whether state was published during the current superstep.
  bool stateUpdated = false;

  /// Gets the checkpoint created during the current superstep, if any.
  CheckpointInfo? checkpoint;

  /// Gets executor IDs instantiated during the current superstep.
  final Set<String> instantiated = <String>{};

  /// Gets executor IDs activated during the current superstep.
  final Set<String> activated = <String>{};

  @override
  void traceInstantiated(String executorId) => instantiated.add(executorId);

  @override
  void traceActivated(String executorId) => activated.add(executorId);

  @override
  void traceStatePublished() => stateUpdated = true;

  @override
  void traceCheckpointCreated(CheckpointInfo cp) => checkpoint = cp;

  /// Resets the tracer to resume from [lastStepNumber].
  void reload([int lastStepNumber = 0]) => _nextStepNumber = lastStepNumber + 1;

  /// Advances to the next superstep and returns the start event.
  SuperStepStartedEvent advance(Map<String, List<Object?>> queuedMessages) {
    _nextStepNumber++;
    activated.clear();
    instantiated.clear();
    stateUpdated = false;
    checkpoint = null;

    var hasExternalMessages = false;
    final sendingExecutors = <String>{};
    for (final key in queuedMessages.keys) {
      if (key.isEmpty) {
        hasExternalMessages = true;
      } else {
        sendingExecutors.add(key);
      }
    }

    return SuperStepStartedEvent(
      stepNumber,
      SuperStepStartInfo(
        sendingExecutors,
        hasExternalMessages: hasExternalMessages,
      ),
    );
  }

  /// Returns the completion event for the current superstep.
  SuperStepCompletedEvent complete({
    required bool nextStepHasActions,
    required bool hasPendingRequests,
  }) => SuperStepCompletedEvent(
    stepNumber,
    SuperStepCompletionInfo(
      activated,
      instantiated,
      hasPendingMessages: nextStepHasActions,
      hasPendingRequests: hasPendingRequests,
      stateUpdated: stateUpdated,
      checkpoint: checkpoint,
    ),
  );

}
