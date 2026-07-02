import 'dart:typed_data';

import '../models/model_spec.dart';

/// Reports model load/download progress as a value from 0 to 1.
typedef LlamaLoadProgress = void Function(double progress);

/// One conversation turn in a structured, engine-neutral shape.
///
/// [LlamaSession.generate] receives the fully rendered prompt string, which
/// is all a token-in/token-out engine needs. Engines whose multimodal path is
/// message-level (the web runtime drives wllama's chat-completion API for
/// image turns) additionally need the conversation as discrete turns; this
/// type carries that view alongside the rendered prompt.
class LlamaChatTurn {
  /// Creates a turn with [role], its concatenated [text], and any [images].
  const LlamaChatTurn({
    required this.role,
    required this.text,
    this.images = const <Uint8List>[],
  });

  /// The chat role: `'system'`, `'user'`, or `'assistant'`.
  final String role;

  /// The turn's text content.
  final String text;

  /// Raw encoded image bytes attached to this turn.
  final List<Uint8List> images;
}

/// A loaded llama-family model session.
///
/// Implementations must yield text with stop sequences removed and terminate at
/// the first stop sequence.
abstract interface class LlamaSession {
  /// Generates text for [prompt], yielding decoded pieces as they arrive.
  ///
  /// [turns] is an optional structured view of the same conversation, used by
  /// runtimes whose multimodal path is message-level; runtimes that consume
  /// the rendered [prompt] directly ignore it.
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
  });

  /// Requests cancellation of any in-flight generation.
  Future<void> cancel();

  /// Releases resources held by this session.
  Future<void> dispose();
}

/// Cross-platform loader for local llama-family model sessions.
abstract interface class LlamaRuntime {
  /// Loads [spec], optionally using already-resolved local artifacts.
  ///
  /// [localPath], [localMmprojPath], and [localDraftPath] are filesystem
  /// paths on native platforms and blob object URLs on the web. When absent,
  /// runtimes fall back to the spec's artifact URLs where supported.
  Future<LlamaSession> loadModel(
    ModelSpec spec, {
    String? localPath,
    String? localMmprojPath,
    String? localDraftPath,
    LlamaLoadProgress? onProgress,
  });
}
