/// On-device LLM inference for iOS and macOS, backed by llama.cpp.
///
/// All native work runs through a Pigeon bridge that is driven from a dedicated
/// worker isolate, so model loading and token streaming never block the UI.
library;

import 'dart:typed_data';

import 'src/llama_isolate.dart';
import 'src/messages.g.dart';

export 'src/llama_isolate.dart' show LlamaException, LlamaGenerationStats;

/// A loaded model session, returned by [LlamaFlutter.loadModel].
class LlamaSession {
  LlamaSession._(this._isolate, this.id);

  final LlamaIsolate _isolate;

  /// Native session identifier.
  final int id;

  /// Generates text for [prompt], yielding decoded tokens as they arrive.
  ///
  /// Generation halts when any string in [stopSequences] appears in the
  /// output; the matched sequence is stripped from the stream. Cancel by
  /// cancelling the returned stream's subscription.
  ///
  /// Pass encoded image bytes (PNG/JPEG) in [images] to feed a vision model;
  /// each entry corresponds, in order, to one media marker in [prompt]. Images
  /// require the session to have been loaded with a `mmprojPath`.
  ///
  /// [topK] and [topP] add the corresponding sampler stages ahead of
  /// temperature sampling; null leaves each stage out. [seed] makes sampling
  /// reproducible; null draws a random seed.
  ///
  /// [onStats] is invoked once when generation completes, with the run's
  /// prompt/cached/generated token counts.
  Stream<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.8,
    int? topK,
    double? topP,
    int? seed,
    List<String> stopSequences = const <String>[],
    List<Uint8List>? images,
    void Function(LlamaGenerationStats)? onStats,
  }) {
    return _isolate.generate(
      GenerationRequest(
        sessionId: id,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topK: topK,
        topP: topP,
        seed: seed,
        stopSequences: stopSequences,
        images: images,
      ),
      onStats: onStats,
    );
  }

  /// Requests cancellation of any in-flight generation for this session.
  Future<void> cancel() => _isolate.cancel(id);

  /// Saves the session's KV-cache state to [path].
  ///
  /// Resolves to the number of tokens the snapshot covers — positive on
  /// success, `0` when nothing is cached (no file is written). Restoring the
  /// file later with [loadState] lets the next [generate] reuse the saved
  /// prompt prefix instead of re-prefilling it (the prompt cache otherwise
  /// only survives while the same conversation stays the session's most
  /// recent one). Throws [LlamaException] on failure.
  Future<int> saveState(String path) =>
      _isolate.sessionState(id, path, save: true);

  /// Restores KV-cache state previously written by [saveState], replacing
  /// the session's current cache.
  ///
  /// Resolves to the number of tokens restored. Throws [LlamaException] when
  /// the file is missing, corrupt, or from an incompatible model; the
  /// session is left with an empty cache in that case, so the next
  /// generation prefills from scratch.
  Future<int> loadState(String path) =>
      _isolate.sessionState(id, path, save: false);

  /// Frees the native model and context for this session.
  Future<void> dispose() => _isolate.disposeSession(id);
}

/// Entry point for llama.cpp inference.
///
/// Create one instance, [loadModel] one or more GGUF files, then [generate]
/// against the returned [LlamaSession]. Call [shutdown] when done to tear down
/// the worker isolate.
class LlamaFlutter {
  final LlamaIsolate _isolate = LlamaIsolate();
  bool _started = false;

  Future<void> _ensureStarted() async {
    if (_started) return;
    await _isolate.start();
    _started = true;
  }

  /// Loads a GGUF model from an absolute filesystem [path].
  ///
  /// [contextSize] is the token context window. [gpuLayers] controls Metal
  /// offload; pass `0` to force CPU (e.g. the iOS Simulator).
  ///
  /// Pass [mmprojPath] (an absolute path to a multimodal projector `.gguf`) to
  /// enable image input via [LlamaSession.generate]'s `images` argument.
  ///
  /// Pass [draftModelPath] (an absolute path to a drafter `.gguf` whose
  /// vocabulary matches the main model, e.g. a Gemma 4 MTP assistant) to
  /// enable speculative decoding: the drafter proposes up to [maxDraftTokens]
  /// tokens per step and the main model verifies them, leaving output
  /// identical but faster. [draftGpuLayers] controls the drafter's Metal
  /// offload independently of [gpuLayers]. Null keeps the session
  /// single-model. The drafter is best-effort: if it fails to load or its
  /// vocabulary is incompatible, the reason is logged natively and the
  /// session loads without speculation rather than failing.
  Future<LlamaSession> loadModel(
    String path, {
    int contextSize = 4096,
    int gpuLayers = 999,
    String? mmprojPath,
    String? draftModelPath,
    int draftGpuLayers = 999,
    int maxDraftTokens = 3,
  }) async {
    await _ensureStarted();
    final id = await _isolate.loadModel(
      ModelLoadRequest(
        modelPath: path,
        contextSize: contextSize,
        gpuLayers: gpuLayers,
        mmprojPath: mmprojPath,
        draftModel: draftModelPath == null
            ? null
            : DraftModelOptions(
                modelPath: draftModelPath,
                gpuLayers: draftGpuLayers,
                maxDraftTokens: maxDraftTokens,
              ),
      ),
    );
    return LlamaSession._(_isolate, id);
  }

  /// Tears down the worker isolate. The instance is unusable afterwards.
  Future<void> shutdown() => _isolate.dispose();
}
