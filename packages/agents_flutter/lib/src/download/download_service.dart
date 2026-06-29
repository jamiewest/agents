import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:extensions/system.dart' show Disposable;

import 'download_request.dart';
import 'download_update.dart';

/// Builds a plugin [DownloadTask] from a [DownloadRequest].
///
/// Extracted as a pure function so the request-to-task mapping can be tested
/// without touching the `FileDownloader` platform singleton. Files are saved
/// under [BaseDirectory.applicationSupport] — app-managed storage for assets
/// like model weights, not user documents — and ask for both status and
/// progress updates so the service can report progress.
DownloadTask buildDownloadTask(DownloadRequest request) => DownloadTask(
  url: request.url,
  filename: request.filename,
  directory: request.directory ?? '',
  baseDirectory: BaseDirectory.applicationSupport,
  headers: request.headers ?? const {},
  updates: Updates.statusAndProgress,
  requiresWiFi: request.requiresWiFi,
  retries: request.retries,
  allowPause: request.allowPause,
  metaData: request.metaData ?? '',
);

/// Minimal download backend used by [DownloadService].
abstract interface class DownloadBackend {
  /// A stream of plugin task updates.
  Stream<TaskUpdate> get updates;

  /// Activates the backend's task tracking and resume behavior.
  Future<void> start();

  /// Downloads [task] and completes with its final plugin status update.
  Future<TaskStatusUpdate> download(
    DownloadTask task, {
    void Function(TaskStatus)? onStatus,
    void Function(double)? onProgress,
  });

  /// Enqueues [task] for background download.
  Future<bool> enqueue(DownloadTask task);

  /// Pauses [task].
  Future<bool> pause(DownloadTask task);

  /// Resumes [task].
  Future<bool> resume(DownloadTask task);

  /// Cancels the task with [taskId].
  Future<bool> cancelTaskWithId(String taskId);

  /// Returns a task by id, if known to the backend.
  Future<Task?> taskForId(String taskId);

  /// Configures download notifications.
  void configureNotification({
    TaskNotification? running,
    TaskNotification? complete,
    TaskNotification? error,
    bool progressBar,
  });
}

// coverage:ignore-start
/// [DownloadBackend] backed by the `background_downloader` plugin.
final class FileDownloaderBackend implements DownloadBackend {
  /// Creates a plugin-backed download backend.
  FileDownloaderBackend({FileDownloader? downloader})
    : _downloader = downloader ?? FileDownloader();

  final FileDownloader _downloader;

  @override
  Stream<TaskUpdate> get updates => _downloader.updates;

  @override
  Future<void> start() => _downloader.start();

  @override
  Future<TaskStatusUpdate> download(
    DownloadTask task, {
    void Function(TaskStatus)? onStatus,
    void Function(double)? onProgress,
  }) {
    return _downloader.download(
      task,
      onStatus: onStatus,
      onProgress: onProgress,
    );
  }

  @override
  Future<bool> enqueue(DownloadTask task) => _downloader.enqueue(task);

  @override
  Future<bool> pause(DownloadTask task) => _downloader.pause(task);

  @override
  Future<bool> resume(DownloadTask task) => _downloader.resume(task);

  @override
  Future<bool> cancelTaskWithId(String taskId) =>
      _downloader.cancelTaskWithId(taskId);

  @override
  Future<Task?> taskForId(String taskId) => _downloader.taskForId(taskId);

  @override
  void configureNotification({
    TaskNotification? running,
    TaskNotification? complete,
    TaskNotification? error,
    bool progressBar = false,
  }) {
    _downloader.configureNotification(
      running: running,
      complete: complete,
      error: error,
      progressBar: progressBar,
    );
  }
}
// coverage:ignore-end

/// Downloads files in the background, surviving the app being backgrounded or
/// killed.
///
/// A thin adapter over `background_downloader`'s [FileDownloader] singleton,
/// exposing plugin-agnostic [DownloadRequest] / [DownloadUpdate] types. Other
/// downloaders compose this service rather than re-implement it — see
/// `HuggingFaceDownloader`.
///
/// Host-app requirements (a library cannot configure these): for true
/// background downloads the embedding app must complete the platform setup in
/// the `background_downloader` README — iOS background `URLSession` and
/// `Info.plist` entries, and Android notification permission plus, for very
/// large files, a foreground service. Call [start] once at app startup so an
/// interrupted download resumes after a restart.
///
/// This is a plain class so callers can compose it and substitute a fake
/// through Dart's implicit interface (`implements DownloadService`) in tests.
class DownloadService implements Disposable {
  /// Creates a service and begins forwarding plugin updates.
  ///
  /// [downloader] defaults to the shared [FileDownloader] singleton and can be
  /// overridden in tests. Most code depends on this concrete type or fakes it
  /// via Dart's implicit interface (`implements DownloadService`).
  DownloadService({FileDownloader? downloader, DownloadBackend? backend})
    : assert(
        downloader == null || backend == null,
        'Provide either downloader or backend, not both.',
      ),
      _backend = backend ?? FileDownloaderBackend(downloader: downloader) {
    _subscription = _backend.updates.listen(_onUpdate, onError: (_) {});
  }

  final DownloadBackend _backend;
  final StreamController<DownloadUpdate> _updates =
      StreamController<DownloadUpdate>.broadcast();
  final Map<String, DownloadTask> _tasks = {};
  late final StreamSubscription<TaskUpdate> _subscription;

  /// A broadcast stream of updates for all enqueued downloads.
  Stream<DownloadUpdate> get updates => _updates.stream;

  /// Activates the task database and reschedules downloads interrupted by an
  /// app restart. Call once at startup.
  Future<void> start() => _backend.start();

  /// Downloads [request] and completes with its final status.
  ///
  /// [onProgress] receives fractional progress (0.0–1.0) and [onStatus] the
  /// status transitions. Prefer [enqueue] for large downloads that should
  /// continue when the app is not in the foreground.
  Future<DownloadStatus> download(
    DownloadRequest request, {
    void Function(double progress)? onProgress,
    void Function(DownloadStatus status)? onStatus,
  }) async {
    final result = await _backend.download(
      buildDownloadTask(request),
      onProgress: onProgress,
      onStatus: onStatus == null
          ? null
          : (status) => onStatus(statusFromTaskStatus(status)),
    );
    return statusFromTaskStatus(result.status);
  }

  /// Enqueues [request] as a background download and returns its task id.
  ///
  /// Progress and completion arrive through [updates]. Returns null if the
  /// platform refused to enqueue the task.
  Future<String?> enqueue(DownloadRequest request) async {
    final task = buildDownloadTask(request);
    _tasks[task.taskId] = task;
    final enqueued = await _backend.enqueue(task);
    if (!enqueued) {
      _tasks.remove(task.taskId);
      return null;
    }
    return task.taskId;
  }

  /// Pauses the download with [taskId], if it is known and pausable.
  Future<bool> pause(String taskId) async {
    final task = await _taskForId(taskId);
    if (task == null) return false;
    return _backend.pause(task);
  }

  /// Resumes the paused download with [taskId], if it is known.
  Future<bool> resume(String taskId) async {
    final task = await _taskForId(taskId);
    if (task == null) return false;
    return _backend.resume(task);
  }

  /// Cancels the download with [taskId].
  Future<bool> cancel(String taskId) => _backend.cancelTaskWithId(taskId);

  /// Configures the OS notifications shown for downloads.
  ///
  /// Recommended for large background downloads: a progress notification keeps
  /// the user informed and, on recent Android, helps the system keep a long
  /// download alive. A null title omits that notification. The body shows the
  /// file name. Requires [start] / platform notification permission to take
  /// effect.
  void configureNotifications({
    String? runningTitle,
    String? completeTitle,
    String? errorTitle,
    bool progressBar = true,
  }) {
    TaskNotification? notification(String? title) =>
        title == null ? null : TaskNotification(title, '{filename}');

    _backend.configureNotification(
      running: notification(runningTitle),
      complete: notification(completeTitle),
      error: notification(errorTitle),
      progressBar: progressBar,
    );
  }

  /// Returns the [DownloadTask] for [taskId], recovering it from the persisted
  /// task database when it is not in the in-memory map (e.g. after an app
  /// restart), or null when no download task is known.
  Future<DownloadTask?> _taskForId(String taskId) async {
    final cached = _tasks[taskId];
    if (cached != null) return cached;
    final recovered = await _backend.taskForId(taskId);
    return recovered is DownloadTask ? recovered : null;
  }

  void _onUpdate(TaskUpdate update) {
    if (update is TaskStatusUpdate && update.status.isFinalState) {
      _tasks.remove(update.task.taskId);
    }
    _updates.add(updateFromTaskUpdate(update));
  }

  @override
  void dispose() {
    _subscription.cancel();
    _updates.close();
  }
}
