import 'workflow_event.dart';

/// Base class for SuperStep-scoped events.
class SuperStepEvent extends WorkflowEvent {
  /// Creates a super-step event.
  const SuperStepEvent(this.stepNumber, {super.data});

  /// Gets the zero-based SuperStep index associated with this event.
  final int stepNumber;

  @override
  String toString() => '$runtimeType(stepNumber: $stepNumber)';
}
