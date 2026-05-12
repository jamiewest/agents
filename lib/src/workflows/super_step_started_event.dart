import 'super_step_event.dart';
import 'super_step_start_info.dart';

/// Event triggered when a SuperStep starts.
class SuperStepStartedEvent extends SuperStepEvent {
  /// Creates a super-step-started event.
  const SuperStepStartedEvent(super.stepNumber, this.info) : super(data: info);

  /// Gets start debug information.
  final SuperStepStartInfo info;
}
