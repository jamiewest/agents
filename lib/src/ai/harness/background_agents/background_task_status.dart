import 'background_agents_provider.dart';

/// Represents the status of a background task managed by the
/// [BackgroundAgentsProvider].
enum BackgroundTaskStatus {
  /// The background task is currently running.
  running,

  /// The background task completed successfully.
  completed,

  /// The background task failed with an error.
  failed,

  /// The background task's in-flight reference was lost (e.g., after a
  /// restart), and its final state cannot be determined.
  lost,
}
