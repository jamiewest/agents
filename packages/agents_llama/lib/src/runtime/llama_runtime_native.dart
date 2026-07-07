import 'dart:typed_data';

import 'package:llama_flutter/llama_flutter.dart' as native;

import '../models/model_spec.dart';
import 'llama_runtime_api.dart';

/// Creates the native llama.cpp runtime for iOS and macOS.
LlamaRuntime createLlamaRuntime() => NativeLlamaRuntime();

/// Loads GGUF models through the `llama_flutter` plugin.
final class NativeLlamaRuntime implements LlamaRuntime {
  NativeLlamaRuntime({native.LlamaFlutter? llama})
    : _llama = llama ?? native.LlamaFlutter();

  final native.LlamaFlutter _llama;

  @override
  bool get supportsMultiThreading => true;

  @override
  Future<LlamaSession> loadModel(
    ModelSpec spec, {
    String? localPath,
    String? localMmprojPath,
    String? localDraftPath,
    LlamaLoadProgress? onProgress,
  }) async {
    if (localPath == null || localPath.isEmpty) {
      throw ArgumentError.value(
        localPath,
        'localPath',
        'Native llama runtime requires a downloaded model path.',
      );
    }

    final session = await _llama.loadModel(
      localPath,
      contextSize: spec.contextSize,
      gpuLayers: spec.gpuLayers,
      mmprojPath: localMmprojPath,
      draftModelPath: localDraftPath,
      draftGpuLayers: spec.draftGpuLayers,
      maxDraftTokens: spec.maxDraftTokens,
    );
    return _NativeLlamaSession(session);
  }
}

final class _NativeLlamaSession implements LlamaSession {
  _NativeLlamaSession(this._inner);

  final native.LlamaSession _inner;

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
    List<LlamaChatTurn>? turns,
    LlamaStatsCallback? onStats,
  }) => _inner.generate(
    prompt,
    maxTokens: maxTokens,
    temperature: temperature,
    topK: topK,
    topP: topP,
    seed: seed,
    stopSequences: stopSequences,
    images: images,
    onStats: onStats == null
        ? null
        : (stats) => onStats(
            LlamaGenerationStats(
              promptTokenCount: stats.promptTokenCount,
              cachedTokenCount: stats.cachedTokenCount,
              generatedTokenCount: stats.generatedTokenCount,
            ),
          ),
  );

  @override
  Future<void> cancel() => _inner.cancel();

  @override
  Future<void> dispose() => _inner.dispose();
}
