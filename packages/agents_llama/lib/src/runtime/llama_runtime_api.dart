import 'dart:typed_data';

import '../models/model_spec.dart';

/// Reports model load/download progress as a value from 0 to 1.
typedef LlamaLoadProgress = void Function(double progress);

/// A loaded llama-family model session.
///
/// Implementations must yield text with stop sequences removed and terminate at
/// the first stop sequence.
abstract interface class LlamaSession {
  /// Generates text for [prompt], yielding decoded pieces as they arrive.
  Stream<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.8,
    int? topK,
    double? topP,
    int? seed,
    List<String> stopSequences = const <String>[],
    List<Uint8List>? images,
  });

  /// Requests cancellation of any in-flight generation.
  Future<void> cancel();

  /// Releases resources held by this session.
  Future<void> dispose();
}

/// Cross-platform loader for local llama-family model sessions.
abstract interface class LlamaRuntime {
  /// Loads [spec], optionally using an already-downloaded native [localPath].
  Future<LlamaSession> loadModel(
    ModelSpec spec, {
    String? localPath,
    LlamaLoadProgress? onProgress,
  });
}
