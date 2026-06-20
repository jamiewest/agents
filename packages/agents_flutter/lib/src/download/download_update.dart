import 'package:background_downloader/background_downloader.dart';

/// The state of a download, independent of the underlying plugin.
enum DownloadStatus {
  /// Queued but not yet started.
  enqueued,

  /// Actively downloading (including waiting to retry).
  running,

  /// Paused and resumable.
  paused,

  /// Finished successfully.
  complete,

  /// Failed, including when the resource was not found.
  failed,

  /// Canceled by the caller.
  canceled,
}

/// An update about an in-flight download, identified by [taskId].
///
/// Mirrors the plugin's two update kinds: a status change
/// ([DownloadStatusUpdate]) and a progress change ([DownloadProgressUpdate]).
sealed class DownloadUpdate {
  const DownloadUpdate(this.taskId);

  /// The id of the download this update is for.
  final String taskId;
}

/// A change in a download's [status].
final class DownloadStatusUpdate extends DownloadUpdate {
  /// Creates a status update for [taskId].
  const DownloadStatusUpdate(super.taskId, this.status);

  /// The new status.
  final DownloadStatus status;
}

/// A change in a download's [progress].
final class DownloadProgressUpdate extends DownloadUpdate {
  /// Creates a progress update for [taskId].
  const DownloadProgressUpdate(super.taskId, this.progress);

  /// Fractional progress from 0.0 to 1.0.
  ///
  /// The plugin reports negative sentinel values for non-progress states; those
  /// are clamped to 0.0.
  final double progress;
}

/// Maps a plugin [TaskStatus] to a [DownloadStatus].
///
/// `notFound` collapses into [DownloadStatus.failed] and `waitingToRetry` into
/// [DownloadStatus.running], since callers treat both the same way.
DownloadStatus statusFromTaskStatus(TaskStatus status) => switch (status) {
  TaskStatus.enqueued => DownloadStatus.enqueued,
  TaskStatus.running => DownloadStatus.running,
  TaskStatus.waitingToRetry => DownloadStatus.running,
  TaskStatus.paused => DownloadStatus.paused,
  TaskStatus.complete => DownloadStatus.complete,
  TaskStatus.canceled => DownloadStatus.canceled,
  TaskStatus.failed => DownloadStatus.failed,
  TaskStatus.notFound => DownloadStatus.failed,
};

/// Maps a plugin [TaskUpdate] to a [DownloadUpdate].
DownloadUpdate updateFromTaskUpdate(TaskUpdate update) => switch (update) {
  TaskStatusUpdate() => DownloadStatusUpdate(
    update.task.taskId,
    statusFromTaskStatus(update.status),
  ),
  TaskProgressUpdate() => DownloadProgressUpdate(
    update.task.taskId,
    update.progress < 0 ? 0.0 : update.progress,
  ),
};
