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

  /// Encodes this task to a JSON-compatible map so the session bag can
  /// serialize it.
  Map<String, Object?> toJson() => {
    'id': id,
    'agentName': agentName,
    'description': description,
    'status': status.name,
    if (resultText != null) 'resultText': resultText,
    if (errorText != null) 'errorText': errorText,
  };

  /// Creates a [BackgroundTaskInfo] from a JSON-decoded map produced by
  /// [toJson].
  static BackgroundTaskInfo fromJson(Map<String, Object?> json) =>
      BackgroundTaskInfo()
        ..id = (json['id'] as num?)?.toInt() ?? 0
        ..agentName = json['agentName'] as String? ?? ''
        ..description = json['description'] as String? ?? ''
        ..status = BackgroundTaskStatus.values.firstWhere(
          (value) => value.name == json['status'],
          orElse: () => BackgroundTaskStatus.lost,
        )
        ..resultText = json['resultText'] as String?
        ..errorText = json['errorText'] as String?;
}
