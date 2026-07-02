import 'dart:typed_data';

import 'package:agents_llama/agents_llama.dart';
import 'package:agents_llama/src/runtime/llama_runtime_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llama_flutter/llama_flutter.dart' as native;

final class _FakeNativeSession implements native.LlamaSession {
  @override
  int get id => 1;

  @override
  Stream<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.8,
    int? topK,
    double? topP,
    int? seed,
    List<String> stopSequences = const <String>[],
    List<Uint8List>? images,
  }) => const Stream<String>.empty();

  @override
  Future<void> cancel() async {}

  @override
  Future<int> saveState(String path) async => 0;

  @override
  Future<int> loadState(String path) async => 0;

  @override
  Future<void> dispose() async {}
}

final class _RecordingLlamaFlutter implements native.LlamaFlutter {
  String? path;
  int? contextSize;
  int? gpuLayers;
  String? mmprojPath;
  String? draftModelPath;
  int? draftGpuLayers;
  int? maxDraftTokens;

  @override
  Future<native.LlamaSession> loadModel(
    String path, {
    int contextSize = 4096,
    int gpuLayers = 999,
    String? mmprojPath,
    String? draftModelPath,
    int draftGpuLayers = 999,
    int maxDraftTokens = 8,
  }) async {
    this.path = path;
    this.contextSize = contextSize;
    this.gpuLayers = gpuLayers;
    this.mmprojPath = mmprojPath;
    this.draftModelPath = draftModelPath;
    this.draftGpuLayers = draftGpuLayers;
    this.maxDraftTokens = maxDraftTokens;
    return _FakeNativeSession();
  }

  @override
  Future<void> shutdown() async {}
}

ModelSpec _spec({int draftGpuLayers = 999, int maxDraftTokens = 8}) =>
    ModelSpec(
      id: 'test-model',
      displayName: 'Test model',
      modelUrl: Uri.parse('https://example.com/model.gguf'),
      contextSize: 2048,
      gpuLayers: 12,
      draftGpuLayers: draftGpuLayers,
      maxDraftTokens: maxDraftTokens,
      format: const Lfm2ChatFormat(),
    );

void main() {
  group('NativeLlamaRuntime.loadModel', () {
    test('forwards projector, draft path, and draft tuning', () async {
      final llama = _RecordingLlamaFlutter();
      final runtime = NativeLlamaRuntime(llama: llama);

      await runtime.loadModel(
        _spec(draftGpuLayers: 4, maxDraftTokens: 16),
        localPath: '/models/main.gguf',
        localMmprojPath: '/models/mmproj.gguf',
        localDraftPath: '/models/draft.gguf',
      );

      expect(llama.path, '/models/main.gguf');
      expect(llama.contextSize, 2048);
      expect(llama.gpuLayers, 12);
      expect(llama.mmprojPath, '/models/mmproj.gguf');
      expect(llama.draftModelPath, '/models/draft.gguf');
      expect(llama.draftGpuLayers, 4);
      expect(llama.maxDraftTokens, 16);
    });

    test('omitted artifacts forward null and keep text-only load', () async {
      final llama = _RecordingLlamaFlutter();
      final runtime = NativeLlamaRuntime(llama: llama);

      await runtime.loadModel(_spec(), localPath: '/models/main.gguf');

      expect(llama.mmprojPath, isNull);
      expect(llama.draftModelPath, isNull);
      expect(llama.draftGpuLayers, 999);
      expect(llama.maxDraftTokens, 8);
    });

    test('requires a local model path', () async {
      final runtime = NativeLlamaRuntime(llama: _RecordingLlamaFlutter());

      expect(() => runtime.loadModel(_spec()), throwsArgumentError);
    });
  });
}
