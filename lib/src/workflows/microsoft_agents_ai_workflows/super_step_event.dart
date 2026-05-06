import 'super_step_completed_event.dart';
import 'workflow_event.dart';

/// Base class for SuperStep-scoped events, for example,
/// [SuperStepCompletedEvent]
class SuperStepEvent extends WorkflowEvent {
  /// Base class for SuperStep-scoped events, for example,
  /// [SuperStepCompletedEvent]
  SuperStepEvent(int stepNumber, {Object? data = null})
    : stepNumber = stepNumber;

  /// The zero-based index of the SuperStep associated with this event.
  final int stepNumber;

  @override
  String toString() {
    return this.data != null
        ? '${this.runtimeType.toString()}(Step = ${this.stepNumber}, Data: ${this.data.runtimeType} = ${this.data})'
        : '${this.runtimeType.toString()}(Step = ${this.stepNumber})';
  }
}
