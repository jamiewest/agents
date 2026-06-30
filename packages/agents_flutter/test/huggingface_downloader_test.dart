import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveUri', () {
    test('builds the resolve URL with the default revision', () {
      final downloader = HuggingFaceDownloader(_FakeDownloadService());

      final uri = downloader.resolveUri(
        'TheBloke/Llama-2-7B-GGUF',
        'llama-2-7b.Q4_K_M.gguf',
      );

      expect(
        uri.toString(),
        'https://huggingface.co/TheBloke/Llama-2-7B-GGUF/resolve/main/'
        'llama-2-7b.Q4_K_M.gguf',
      );
    });

    test('honors a custom revision', () {
      final downloader = HuggingFaceDownloader(_FakeDownloadService());

      final uri = downloader.resolveUri(
        'org/model',
        'weights.safetensors',
        revision: 'v2',
      );

      expect(
        uri.toString(),
        'https://huggingface.co/org/model/resolve/v2/weights.safetensors',
      );
    });
  });

  group('enqueueModel', () {
    test(
      'enqueues a request with the resolve URL and default directory',
      () async {
        final downloads = _FakeDownloadService();
        final downloader = HuggingFaceDownloader(downloads);

        final taskId = await downloader.enqueueModel(
          repoId: 'org/model',
          filename: 'weights.gguf',
        );

        expect(taskId, 'fake-task');
        final request = downloads.lastEnqueued!;
        expect(
          request.url,
          'https://huggingface.co/org/model/resolve/main/weights.gguf',
        );
        expect(request.filename, 'weights.gguf');
        expect(request.directory, 'org/model');
        expect(request.headers, isNull);
        expect(request.metaData, 'org/model');
      },
    );

    test('adds an auth header when a token is set', () async {
      final downloads = _FakeDownloadService();
      final downloader = HuggingFaceDownloader(downloads, token: 'hf_secret');

      await downloader.enqueueModel(repoId: 'org/model', filename: 'a.bin');

      expect(downloads.lastEnqueued!.headers, {
        'Authorization': 'Bearer hf_secret',
      });
    });

    test('saves nested files under their base name', () async {
      final downloads = _FakeDownloadService();
      final downloader = HuggingFaceDownloader(downloads);

      await downloader.enqueueModel(
        repoId: 'org/model',
        filename: 'onnx/decoder_model.onnx',
        directory: 'custom',
      );

      final request = downloads.lastEnqueued!;
      expect(request.filename, 'decoder_model.onnx');
      expect(
        request.url,
        'https://huggingface.co/org/model/resolve/main/onnx/decoder_model.onnx',
      );
      expect(request.directory, 'custom');
    });
  });

  group('downloadModel', () {
    test('forwards progress and returns the mapped status', () async {
      final downloads = _FakeDownloadService(
        downloadResult: DownloadStatus.complete,
      );
      final downloader = HuggingFaceDownloader(downloads);
      final progress = <double>[];

      final status = await downloader.downloadModel(
        repoId: 'org/model',
        filename: 'a.bin',
        onProgress: progress.add,
      );

      expect(status, DownloadStatus.complete);
      expect(progress, [0.5, 1.0]);
    });
  });

  group('listFiles', () {
    test('parses siblings, sha, gated, and private', () async {
      const body = '''
      {
        "sha": "abc123",
        "gated": "auto",
        "private": false,
        "siblings": [
          {"rfilename": "config.json"},
          {"rfilename": "onnx/decoder_model.onnx"},
          {"bogus": true}
        ]
      }''';
      final api = HuggingFaceApi(
        token: 'hf_secret',
        httpGet: (url, {headers}) async {
          expect(url.toString(), 'https://huggingface.co/api/models/org/model');
          expect(headers, {'Authorization': 'Bearer hf_secret'});
          return body;
        },
      );
      final downloader = HuggingFaceDownloader(
        _FakeDownloadService(),
        api: api,
      );

      final info = await downloader.listFiles('org/model');

      expect(info.sha, 'abc123');
      expect(info.gated, isTrue);
      expect(info.private, isFalse);
      expect(info.files.map((file) => file.path), [
        'config.json',
        'onnx/decoder_model.onnx',
      ]);
    });

    test('uses the revision endpoint and omits auth without a token', () async {
      final api = HuggingFaceApi(
        httpGet: (url, {headers}) async {
          expect(
            url.toString(),
            'https://huggingface.co/api/models/org/model/revision/v2',
          );
          expect(headers, isNull);
          return '{"siblings": []}';
        },
      );

      final info = await api.listFiles('org/model', revision: 'v2');

      expect(info.files, isEmpty);
      expect(info.gated, isFalse);
    });

    test('throws on a transport error', () async {
      final api = HuggingFaceApi(
        httpGet: (url, {headers}) async =>
            throw const HuggingFaceApiException('boom'),
      );

      expect(
        () => api.listFiles('org/model'),
        throwsA(isA<HuggingFaceApiException>()),
      );
    });
  });
}

final class _FakeDownloadService implements DownloadService {
  _FakeDownloadService({this.downloadResult = DownloadStatus.complete});

  final DownloadStatus downloadResult;
  DownloadRequest? lastEnqueued;

  @override
  Future<String?> enqueue(DownloadRequest request) async {
    lastEnqueued = request;
    return 'fake-task';
  }

  @override
  Future<DownloadStatus> download(
    DownloadRequest request, {
    void Function(double progress)? onProgress,
    void Function(DownloadStatus status)? onStatus,
  }) async {
    onProgress?.call(0.5);
    onProgress?.call(1.0);
    return downloadResult;
  }

  @override
  Future<String> filePathFor(DownloadRequest request) async =>
      '/tmp/${request.filename}';

  @override
  Stream<DownloadUpdate> get updates => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<bool> pause(String taskId) async => false;

  @override
  Future<bool> resume(String taskId) async => false;

  @override
  Future<bool> cancel(String taskId) async => false;

  @override
  void configureNotifications({
    String? runningTitle,
    String? completeTitle,
    String? errorTitle,
    bool progressBar = true,
  }) {}

  @override
  void dispose() {}
}
