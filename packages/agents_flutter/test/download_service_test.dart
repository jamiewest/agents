import 'dart:async';

import 'package:agents_flutter/agents_flutter.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildDownloadTask', () {
    test('maps the request onto an app-support download task', () {
      final fileSystem = MemoryFileSystem.test();
      final directory = fileSystem.directory('models/llama').path;
      const request = DownloadRequest(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        directory: null,
        headers: {'Authorization': 'Bearer secret'},
        requiresWiFi: true,
        retries: 5,
        metaData: 'meta',
      );
      final requestWithDirectory = DownloadRequest(
        url: request.url,
        filename: request.filename,
        directory: directory,
        headers: request.headers,
        requiresWiFi: request.requiresWiFi,
        retries: request.retries,
        metaData: request.metaData,
      );

      final task = buildDownloadTask(requestWithDirectory);

      expect(task.url, 'https://example.com/model.gguf');
      expect(task.filename, 'model.gguf');
      expect(task.directory, 'models/llama');
      expect(task.baseDirectory, BaseDirectory.applicationSupport);
      expect(task.headers, {'Authorization': 'Bearer secret'});
      expect(task.updates, Updates.statusAndProgress);
      expect(task.requiresWiFi, isTrue);
      expect(task.retries, 5);
      expect(task.allowPause, isTrue);
      expect(task.metaData, 'meta');
    });

    test('applies large-file defaults for optional fields', () {
      const request = DownloadRequest(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
      );

      final task = buildDownloadTask(request);

      expect(task.directory, '');
      expect(task.headers, isEmpty);
      expect(task.requiresWiFi, isFalse);
      expect(task.retries, 3);
      expect(task.allowPause, isTrue);
    });
  });

  group('statusFromTaskStatus', () {
    test('maps each plugin status to a domain status', () {
      expect(
        statusFromTaskStatus(TaskStatus.enqueued),
        DownloadStatus.enqueued,
      );
      expect(statusFromTaskStatus(TaskStatus.running), DownloadStatus.running);
      expect(
        statusFromTaskStatus(TaskStatus.waitingToRetry),
        DownloadStatus.running,
      );
      expect(statusFromTaskStatus(TaskStatus.paused), DownloadStatus.paused);
      expect(
        statusFromTaskStatus(TaskStatus.complete),
        DownloadStatus.complete,
      );
      expect(
        statusFromTaskStatus(TaskStatus.canceled),
        DownloadStatus.canceled,
      );
      expect(statusFromTaskStatus(TaskStatus.failed), DownloadStatus.failed);
      expect(statusFromTaskStatus(TaskStatus.notFound), DownloadStatus.failed);
    });
  });

  group('updateFromTaskUpdate', () {
    final task = DownloadTask(taskId: 'abc', url: 'https://example.com/a');

    test('maps a status update', () {
      final update = updateFromTaskUpdate(
        TaskStatusUpdate(task, TaskStatus.complete),
      );

      expect(update, isA<DownloadStatusUpdate>());
      final status = update as DownloadStatusUpdate;
      expect(status.taskId, 'abc');
      expect(status.status, DownloadStatus.complete);
    });

    test('maps a progress update and clamps sentinel values', () {
      final update = updateFromTaskUpdate(TaskProgressUpdate(task, 0.5));
      final negative = updateFromTaskUpdate(TaskProgressUpdate(task, -1));

      expect((update as DownloadProgressUpdate).progress, 0.5);
      expect(update.taskId, 'abc');
      expect((negative as DownloadProgressUpdate).progress, 0.0);
    });
  });

  group('DownloadService', () {
    test('start delegates to the backend', () async {
      final backend = _FakeDownloadBackend();
      final service = DownloadService(backend: backend);

      await service.start();

      expect(backend.started, isTrue);
      service.dispose();
      await backend.dispose();
    });

    test('download forwards callbacks and maps the final status', () async {
      final backend = _FakeDownloadBackend(downloadStatus: TaskStatus.failed);
      final service = DownloadService(backend: backend);
      final statuses = <DownloadStatus>[];
      final progress = <double>[];

      final result = await service.download(
        const DownloadRequest(
          url: 'https://example.com/model.gguf',
          filename: 'model.gguf',
        ),
        onStatus: statuses.add,
        onProgress: progress.add,
      );

      expect(result, DownloadStatus.failed);
      expect(statuses, [DownloadStatus.running]);
      expect(progress, [0.25]);
      expect(backend.downloadedTask!.url, 'https://example.com/model.gguf');
      service.dispose();
      await backend.dispose();
    });

    test('enqueue returns a task id and uses cached tasks for pause', () async {
      final backend = _FakeDownloadBackend();
      final service = DownloadService(backend: backend);

      final taskId = await service.enqueue(
        const DownloadRequest(
          url: 'https://example.com/model.gguf',
          filename: 'model.gguf',
        ),
      );
      final paused = await service.pause(taskId!);

      expect(taskId, backend.enqueuedTask!.taskId);
      expect(paused, isTrue);
      expect(backend.pausedTasks.single, same(backend.enqueuedTask));
      expect(backend.taskForIdCalls, isEmpty);
      service.dispose();
      await backend.dispose();
    });

    test('enqueue failure removes the cached task', () async {
      final backend = _FakeDownloadBackend(enqueueResult: false);
      final service = DownloadService(backend: backend);

      final taskId = await service.enqueue(
        const DownloadRequest(
          url: 'https://example.com/model.gguf',
          filename: 'model.gguf',
        ),
      );
      final paused = await service.pause(backend.enqueuedTask!.taskId);

      expect(taskId, isNull);
      expect(paused, isFalse);
      expect(backend.taskForIdCalls, [backend.enqueuedTask!.taskId]);
      expect(backend.pausedTasks, isEmpty);
      service.dispose();
      await backend.dispose();
    });

    test('pause and resume can recover tasks from the backend', () async {
      final backend = _FakeDownloadBackend();
      final service = DownloadService(backend: backend);
      final task = DownloadTask(
        taskId: 'known-task',
        url: 'https://example.com/model.gguf',
      );
      backend.recoveredTasks[task.taskId] = task;

      final paused = await service.pause(task.taskId);
      final resumed = await service.resume(task.taskId);
      final missing = await service.resume('missing');

      expect(paused, isTrue);
      expect(resumed, isTrue);
      expect(missing, isFalse);
      expect(backend.pausedTasks.single, same(task));
      expect(backend.resumedTasks.single, same(task));
      service.dispose();
      await backend.dispose();
    });

    test('cancel delegates by task id', () async {
      final backend = _FakeDownloadBackend(cancelResult: true);
      final service = DownloadService(backend: backend);

      final canceled = await service.cancel('abc');

      expect(canceled, isTrue);
      expect(backend.canceledTaskIds, ['abc']);
      service.dispose();
      await backend.dispose();
    });

    test(
      'forwards plugin updates and removes completed cached tasks',
      () async {
        final backend = _FakeDownloadBackend();
        final service = DownloadService(backend: backend);
        final taskId = await service.enqueue(
          const DownloadRequest(
            url: 'https://example.com/model.gguf',
            filename: 'model.gguf',
          ),
        );
        final update = expectLater(
          service.updates,
          emits(
            isA<DownloadStatusUpdate>()
                .having((update) => update.taskId, 'taskId', taskId)
                .having(
                  (update) => update.status,
                  'status',
                  DownloadStatus.complete,
                ),
          ),
        );

        backend.emit(
          TaskStatusUpdate(backend.enqueuedTask!, TaskStatus.complete),
        );
        await update;
        final paused = await service.pause(taskId!);

        expect(paused, isFalse);
        expect(backend.taskForIdCalls, [taskId]);
        service.dispose();
        await backend.dispose();
      },
    );

    test('configureNotifications maps titles and progress setting', () async {
      final backend = _FakeDownloadBackend();
      final service = DownloadService(backend: backend);

      service.configureNotifications(
        runningTitle: 'Downloading',
        completeTitle: 'Done',
        errorTitle: 'Failed',
        progressBar: true,
      );

      expect(backend.runningNotification!.title, 'Downloading');
      expect(backend.runningNotification!.body, '{filename}');
      expect(backend.completeNotification!.title, 'Done');
      expect(backend.errorNotification!.title, 'Failed');
      expect(backend.progressBar, isTrue);
      service.dispose();
      await backend.dispose();
    });

    test('dispose closes the public updates stream', () async {
      final backend = _FakeDownloadBackend();
      final service = DownloadService(backend: backend);
      final done = expectLater(service.updates, emitsDone);

      service.dispose();

      await done;
      await backend.dispose();
    });
  });

  group('registration', () {
    test('addDownloadService preserves an existing service', () {
      final existing = DownloadService(backend: _FakeDownloadBackend());
      final services = ServiceCollection()
        ..addSingletonInstance<DownloadService>(existing)
        ..addDownloadService();
      final serviceProvider = services.buildServiceProvider();

      expect(
        serviceProvider.getRequiredService<DownloadService>(),
        same(existing),
      );
      existing.dispose();
    });

    test('addHuggingFaceDownloader registers dependencies', () {
      final downloadService = DownloadService(backend: _FakeDownloadBackend());
      final services = ServiceCollection()
        ..addSingletonInstance<DownloadService>(downloadService)
        ..addHuggingFaceDownloader(token: 'hf_secret');
      final serviceProvider = services.buildServiceProvider();

      expect(
        serviceProvider.getRequiredService<DownloadService>(),
        same(downloadService),
      );
      expect(
        serviceProvider.getRequiredService<HuggingFaceDownloader>(),
        isA<HuggingFaceDownloader>(),
      );
      downloadService.dispose();
    });

    test('addHuggingFaceDownloader preserves an existing downloader', () {
      final downloadService = DownloadService(backend: _FakeDownloadBackend());
      final existing = HuggingFaceDownloader(downloadService);
      final services = ServiceCollection()
        ..addSingletonInstance<DownloadService>(downloadService)
        ..addSingletonInstance<HuggingFaceDownloader>(existing)
        ..addHuggingFaceDownloader(token: 'hf_secret');
      final serviceProvider = services.buildServiceProvider();

      expect(
        serviceProvider.getRequiredService<HuggingFaceDownloader>(),
        same(existing),
      );
      downloadService.dispose();
    });
  });
}

final class _FakeDownloadBackend implements DownloadBackend {
  _FakeDownloadBackend({
    this.downloadStatus = TaskStatus.complete,
    this.enqueueResult = true,
    this.cancelResult = false,
  });

  final TaskStatus downloadStatus;
  final bool enqueueResult;
  final bool cancelResult;
  final StreamController<TaskUpdate> _updates =
      StreamController<TaskUpdate>.broadcast();

  bool started = false;
  DownloadTask? downloadedTask;
  DownloadTask? enqueuedTask;
  final recoveredTasks = <String, Task>{};
  final taskForIdCalls = <String>[];
  final pausedTasks = <DownloadTask>[];
  final resumedTasks = <DownloadTask>[];
  final canceledTaskIds = <String>[];
  TaskNotification? runningNotification;
  TaskNotification? completeNotification;
  TaskNotification? errorNotification;
  bool? progressBar;

  @override
  Stream<TaskUpdate> get updates => _updates.stream;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<TaskStatusUpdate> download(
    DownloadTask task, {
    void Function(TaskStatus)? onStatus,
    void Function(double)? onProgress,
  }) async {
    downloadedTask = task;
    onStatus?.call(TaskStatus.running);
    onProgress?.call(0.25);
    return TaskStatusUpdate(task, downloadStatus);
  }

  @override
  Future<bool> enqueue(DownloadTask task) async {
    enqueuedTask = task;
    return enqueueResult;
  }

  @override
  Future<bool> pause(DownloadTask task) async {
    pausedTasks.add(task);
    return true;
  }

  @override
  Future<bool> resume(DownloadTask task) async {
    resumedTasks.add(task);
    return true;
  }

  @override
  Future<bool> cancelTaskWithId(String taskId) async {
    canceledTaskIds.add(taskId);
    return cancelResult;
  }

  @override
  Future<Task?> taskForId(String taskId) async {
    taskForIdCalls.add(taskId);
    return recoveredTasks[taskId];
  }

  @override
  void configureNotification({
    TaskNotification? running,
    TaskNotification? complete,
    TaskNotification? error,
    bool progressBar = false,
  }) {
    runningNotification = running;
    completeNotification = complete;
    errorNotification = error;
    this.progressBar = progressBar;
  }

  void emit(TaskUpdate update) => _updates.add(update);

  Future<void> dispose() => _updates.close();
}
