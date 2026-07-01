import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'darwin/Classes/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'LlamaError'),
    dartPackageName: 'llama_flutter',
  ),
)
/// Parameters for an optional drafter (assistant) model that enables
/// speculative decoding.
///
/// The drafter proposes tokens cheaply and the main model verifies them, so
/// the output distribution is identical to decoding with the main model
/// alone — just faster when the drafter's guesses are accepted. Any GGUF
/// whose vocabulary matches the main model works (e.g. a Gemma 4 MTP
/// `*-assistant` drafter); this is not tied to one architecture.
class DraftModelOptions {
  DraftModelOptions({
    required this.modelPath,
    required this.gpuLayers,
    required this.maxDraftTokens,
  });

  /// Absolute filesystem path to the drafter `.gguf`.
  String modelPath;

  /// Number of drafter layers to offload to the GPU (`n_gpu_layers`).
  ///
  /// `0` forces CPU-only inference (e.g. the iOS Simulator).
  int gpuLayers;

  /// Maximum tokens drafted per verification step.
  int maxDraftTokens;
}

/// Parameters for loading a GGUF model into a native llama.cpp session.
class ModelLoadRequest {
  ModelLoadRequest({
    required this.modelPath,
    required this.contextSize,
    required this.gpuLayers,
    this.mmprojPath,
    this.draftModel,
  });

  /// Absolute filesystem path to the `.gguf` model.
  String modelPath;

  /// Context window size (`n_ctx`).
  int contextSize;

  /// Number of layers to offload to the GPU (`n_gpu_layers`).
  ///
  /// `0` forces CPU-only inference (e.g. the iOS Simulator).
  int gpuLayers;

  /// Absolute path to the multimodal projector (`mmproj`) `.gguf`.
  ///
  /// When non-null the session also stands up an `mtmd` context, enabling
  /// image input via [GenerationRequest.images]. Null keeps the session
  /// text-only.
  String? mmprojPath;

  /// Optional drafter model enabling speculative decoding.
  ///
  /// Null disables speculation; the session then behaves exactly as a
  /// single-model session.
  DraftModelOptions? draftModel;
}

/// Parameters for a single generation run against a loaded session.
class GenerationRequest {
  GenerationRequest({
    required this.sessionId,
    required this.prompt,
    required this.maxTokens,
    required this.temperature,
    this.topK,
    this.topP,
    this.seed,
    required this.stopSequences,
    this.images,
  });

  /// Session returned by [LlamaHostApi.loadModel].
  int sessionId;

  /// The fully formatted prompt to feed the model.
  String prompt;

  /// Hard cap on the number of tokens to generate.
  int maxTokens;

  /// Sampling temperature; `0` is greedy.
  double temperature;

  /// Top-k cutoff applied before temperature sampling. Null or `<= 0`
  /// disables the top-k stage.
  int? topK;

  /// Nucleus (top-p) cutoff applied before temperature sampling. Null or
  /// `>= 1.0` disables the top-p stage.
  double? topP;

  /// Sampler seed for reproducible generation. Null draws a random seed.
  int? seed;

  /// Strings that, when produced in the decoded output, halt generation.
  ///
  /// The matched stop sequence is removed from the streamed text and is not
  /// emitted. Matching runs against the decoded text (with special tokens
  /// rendered), so control markers such as Gemma's `<turn|>` work directly.
  /// Empty disables stop-sequence handling.
  List<String> stopSequences;

  /// Encoded image bytes (PNG/JPEG) to feed alongside [prompt].
  ///
  /// Each entry corresponds, in order, to one media marker in [prompt]. Only
  /// honoured when the session was loaded with a
  /// [ModelLoadRequest.mmprojPath]; otherwise ignored. Null or empty runs a
  /// text-only generation.
  List<Uint8List>? images;
}

/// A single streamed generation event.
///
/// Emitted repeatedly with [text] set while tokens are produced, then once
/// more with [done] true. On failure [error] is set and [done] is true.
class TokenEvent {
  TokenEvent({
    required this.sessionId,
    this.text,
    required this.done,
    this.error,
  });

  int sessionId;
  String? text;
  bool done;
  String? error;
}

/// Control surface implemented natively (Swift) and called from Dart.
@HostApi()
abstract class LlamaHostApi {
  /// Loads the model and returns an opaque session id.
  @async
  int loadModel(ModelLoadRequest request);

  /// Starts generation; tokens arrive on the [LlamaTokenStream] event channel.
  void startGeneration(GenerationRequest request);

  /// Requests cancellation of an in-flight generation for [sessionId].
  void cancelGeneration(int sessionId);

  /// Saves the session's KV-cache state (and its token ledger) to [path].
  ///
  /// Returns the number of tokens covered by the snapshot: positive on
  /// success, `0` when the session holds no reusable cache (no file is
  /// written). Runs on the session's serial queue, so it cannot interleave
  /// with generation.
  @async
  int saveSessionState(int sessionId, String path);

  /// Restores KV-cache state previously written by [saveSessionState].
  ///
  /// Replaces the session's current cache contents. Returns the number of
  /// tokens restored. Fails (throws) when the file is missing, corrupt, or
  /// was written by an incompatible model — the session is left with an
  /// empty cache in that case, so the next generation simply prefills from
  /// scratch.
  @async
  int loadSessionState(int sessionId, String path);

  /// Frees the model/context associated with [sessionId].
  void disposeSession(int sessionId);
}

/// Token stream delivered from native to Dart via an `EventChannel`.
///
/// A single stream multiplexes every session's tokens; each [TokenEvent]
/// carries its [TokenEvent.sessionId] so listeners can filter per session.
@EventChannelApi()
abstract class LlamaTokenStream {
  TokenEvent streamTokens();
}
