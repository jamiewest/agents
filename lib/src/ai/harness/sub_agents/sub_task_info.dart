import 'sub_agents_provider.dart';
import 'sub_task_status.dart';

/// Represents the metadata and result of a sub-task managed by the
/// [SubAgentsProvider].
class SubTaskInfo {
  SubTaskInfo();

  /// Gets or sets the unique identifier for this sub-task.
  int id = 0;

  /// Gets or sets the name of the agent that is executing this sub-task.
  String agentName = '';

  /// Gets or sets a description of what this sub-task is doing.
  String description = '';

  /// Gets or sets the current status of this sub-task.
  SubTaskStatus status = SubTaskStatus.running;

  /// Gets or sets the text result of the sub-task, populated when the task
  /// completes successfully.
  String? resultText;

  /// Gets or sets the error message if the sub-task failed.
  String? errorText;
}
