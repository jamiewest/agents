import 'package:agents_flutter/agents_flutter.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildDownloadTask', () {
    test('maps the request onto an app-support download task', () {
      const request = DownloadRequest(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        directory: 'models/llama',
        headers: {'Authorization': 'Bearer secret'},
        requiresWiFi: true,
        retries: 5,
        metaData: 'meta',
      );

      final task = buildDownloadTask(request);

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
}
