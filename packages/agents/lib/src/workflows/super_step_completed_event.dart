import 'super_step_completion_info.dart';
import 'super_step_event.dart';

/// Event triggered when a SuperStep completes.
class SuperStepCompletedEvent extends SuperStepEvent {
  /// Creates a super-step-completed event.
  const SuperStepCompletedEvent(super.stepNumber, this.info)
    : super(data: info);

  /// Gets completion debug information.
  final SuperStepCompletionInfo info;
}
