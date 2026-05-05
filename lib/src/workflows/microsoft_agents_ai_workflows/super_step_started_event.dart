import 'super_step_event.dart';
import 'super_step_start_info.dart';

/// Event triggered when a SuperStep started.
///
/// [stepNumber] The zero-based index of the SuperStep associated with this
/// event.
///
/// [startInfo] Debug information about the state of the system on SuperStep
/// start.
class SuperStepStartedEvent extends SuperStepEvent {
  /// Event triggered when a SuperStep started.
  ///
  /// [stepNumber] The zero-based index of the SuperStep associated with this
  /// event.
  ///
  /// [startInfo] Debug information about the state of the system on SuperStep
  /// start.
  SuperStepStartedEvent(int stepNumber, {SuperStepStartInfo? startInfo = null});

  /// Gets the debug information about the state of the system on SuperStep
  /// start.
  SuperStepStartInfo? get startInfo {
    return startInfo;
  }
}
