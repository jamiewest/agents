import 'super_step_completion_info.dart';
import 'super_step_event.dart';

/// Event triggered when a SuperStep completed.
///
/// [stepNumber] The zero-based index of the SuperStep associated with this
/// event.
///
/// [completionInfo] Debug information about the state of the system on
/// SuperStep completion.
class SuperStepCompletedEvent extends SuperStepEvent {
  /// Event triggered when a SuperStep completed.
  ///
  /// [stepNumber] The zero-based index of the SuperStep associated with this
  /// event.
  ///
  /// [completionInfo] Debug information about the state of the system on
  /// SuperStep completion.
  SuperStepCompletedEvent(
    int stepNumber, {
    SuperStepCompletionInfo? completionInfo = null,
  });

  /// Gets the debug information about the state of the system on SuperStep
  /// completion.
  SuperStepCompletionInfo? get completionInfo {
    return completionInfo;
  }
}
