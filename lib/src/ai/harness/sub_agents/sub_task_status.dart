import 'sub_agents_provider.dart';

/// Represents the status of a sub-task managed by the [SubAgentsProvider].
enum SubTaskStatus {
  /// The sub-task is currently running.
  running,

  /// The sub-task completed successfully.
  completed,

  /// The sub-task failed with an error.
  failed,

  /// The sub-task's in-flight reference was lost (e.g., after a restart), and
  /// its final state cannot be determined.
  lost,
}
