import '../checkpoint_info.dart';
import '../execution/executor_identity.dart';
import '../execution/step_context.dart';
import '../execution/step_tracer.dart';
import '../super_step_completed_event.dart';
import '../super_step_completion_info.dart';
import '../super_step_start_info.dart';
import '../super_step_started_event.dart';

class InProcStepTracer implements StepTracer {
  InProcStepTracer();

  late int _nextStepNumber;

  late bool stateUpdated;

  late CheckpointInfo? checkpoint;

  final Map<String, String> instantiated;

  final Map<String, String> activated;

  int get stepNumber {
    return this._nextStepNumber - 1;
  }

  @override
  void traceIntantiated(String executorId) {
    this.instantiated.tryAdd(executorId, executorId);
  }

  @override
  void traceActivated(String executorId) {
    this.activated.tryAdd(executorId, executorId);
  }

  @override
  void traceStatePublished() {
    this.stateUpdated = true;
  }

  @override
  void traceCheckpointCreated(CheckpointInfo checkpoint) {
    this.checkpoint = checkpoint;
  }

  /// Reset the tracer to the specified step number.
  ///
  /// [lastStepNumber] The Step Number of the last SuperStep. Note that Step
  /// Numbers are 0-indexed.
  void reload({int? lastStepNumber}) {
    this._nextStepNumber = lastStepNumber + 1;
  }

  SuperStepStartedEvent advance(StepContext step) {
    this._nextStepNumber++;
    this.activated.clear();
    this.instantiated.clear();
    this.stateUpdated = false;
    this.checkpoint = null;
    var sendingExecutors = [];
    var hasExternalMessages = false;
    for (final identity in step.queuedMessages.keys) {
      if (identity == ExecutorIdentity.none) {
        hasExternalMessages = true;
      } else {
        sendingExecutors.add(identity.id!);
      }
    }
    return superStepStartedEvent(this.stepNumber, superStepStartInfo(sendingExecutors));
  }

  SuperStepCompletedEvent complete(bool nextStepHasActions, bool hasPendingRequests, ) {
    return new(
      this.stepNumber,
      superStepCompletionInfo(this.activated.keys, this.instantiated.keys),
    );
  }

  @override
  String toString() {
    var sb = new();
    if (!this.instantiated.isEmpty) {
      sb.write("instantiated: ").write(this.instantiated.keys.orderBy((id.join(", ") => id, )));
    }
    if (!this.activated.isEmpty) {
      if (sb.length != 0) {
        sb.writeln();
      }
      sb.write("activated: ").write(this.activated.keys.orderBy((id.join(", ") => id, )));
    }
    return sb.toString();
  }
}
