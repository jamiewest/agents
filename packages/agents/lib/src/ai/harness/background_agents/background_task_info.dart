import 'background_agents_provider.dart';
import 'background_task_status.dart';

/// Represents the metadata and result of a background task managed by the
/// [BackgroundAgentsProvider].
class BackgroundTaskInfo {
  BackgroundTaskInfo();

  /// Unique identifier for this background task.
  int id = 0;

  /// Name of the agent that is executing this background task.
  String agentName = '';

  /// Description of what this background task is doing.
  String description = '';

  /// Current status of this background task.
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  /// Text result of the background task, populated when the task completes
  /// successfully.
  String? resultText;

  /// Error message if the background task failed.
  String? errorText;
}
