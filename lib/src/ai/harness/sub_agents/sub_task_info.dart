import 'sub_agents_provider.dart';
import 'sub_task_status.dart';

/// Represents the metadata and result of a sub-task managed by the
/// [SubAgentsProvider].
class SubTaskInfo {
  SubTaskInfo();

  /// Unique identifier for this sub-task.
  int id = 0;

  /// Name of the agent that is executing this sub-task.
  String agentName = '';

  /// Description of what this sub-task is doing.
  String description = '';

  /// Current status of this sub-task.
  SubTaskStatus status = SubTaskStatus.running;

  /// Text result of the sub-task, populated when the task completes
  /// successfully.
  String? resultText;

  /// Error message if the sub-task failed.
  String? errorText;
}
