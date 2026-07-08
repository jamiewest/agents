/// Declarative description of an on-device model: where its artifacts live,
/// how to configure the engine, and which chat format it speaks.
library;

import '../llm/chat_format.dart';

/// A model's preferred sampling parameters, used when the per-request
/// `ChatOptions` doesn't override them.
class SamplingDefaults {
  const SamplingDefaults({
    this.maxTokens = 512,
    this.temperature = 1.0,
    this.topK,
    this.topP,
    this.seed,
  });

  /// Max tokens per generated turn.
  final int maxTokens;

  /// Sampling temperature.
  final double temperature;

  /// Top-k cutoff, or null for the engine default.
  final int? topK;

  /// Nucleus-sampling cutoff, or null for the engine default.
  final double? topP;

  /// Sampler seed for reproducible generation, or null for random.
  final int? seed;
}

/// Everything the app needs to provision and run one model: artifact URLs,
/// engine configuration, the [ChatFormat] it speaks, and sampling defaults.
///
/// Specs are plain data declared in `model_registry.dart`; services
/// (download, load, chat client construction) consume whichever spec is
/// registered, so switching models is a registry change, not a code hunt.
class ModelSpec {
  ModelSpec({
    required this.id,
    required this.displayName,
    required this.modelUrl,
    this.mmprojUrl,
    this.draftUrl,
    required this.contextSize,
    this.gpuLayers = 999,
    this.draftGpuLayers = 999,
    this.maxDraftTokens = 3,
    required this.format,
    this.sampling = const SamplingDefaults(),
    this.engineId = 'llama',
    this.filterTools = true,
    this.enableThinking = true,
  });

  /// Stable identifier, e.g. `'gemma-4-e4b-it-q4km'`.
  final String id;

  /// Human-readable name for UI surfaces.
  final String displayName;

  /// Where the model weights are downloaded from.
  final Uri modelUrl;

  /// The multimodal projector pairing with [modelUrl] (mtmd vision), or null
  /// for a text-only model.
  final Uri? mmprojUrl;

  /// The speculative-decoding drafter pairing with [modelUrl], or null to
  /// decode single-model.
  final Uri? draftUrl;

  /// Context window the engine allocates at load time.
  final int contextSize;

  /// GPU offload hint (llama.cpp layer count; 999 = everything on Metal).
  /// Engines that don't split layers ignore it.
  final int gpuLayers;

  /// GPU offload hint for the speculative-decoding drafter; only meaningful
  /// when [draftUrl] (or a locally selected draft artifact) is configured.
  final int draftGpuLayers;

  /// Upper bound on tokens the drafter proposes per speculation step.
  ///
  /// Defaults to 3, matching upstream llama.cpp's speculative n_max: at
  /// sampling temperatures the per-token acceptance rate makes longer draft
  /// chains net-negative (every rejected token costs a wasted draft decode
  /// plus a wasted verification slot).
  final int maxDraftTokens;

  /// The model family's prompt wire format.
  final ChatFormat format;

  /// Sampling parameters used when `ChatOptions` doesn't override them.
  final SamplingDefaults sampling;

  /// Whether per-turn keyword tool selection applies to this model's prompts.
  ///
  /// `true` (default) keeps `ToolSelectionContextProvider` in the agent's
  /// context-provider chain, shrinking the per-turn tool list to keyword-matched
  /// groups — a prefill/KV-cache win for capable models. Set `false` for a
  /// less-capable model where a keyword miss (a needed tool dropped from the
  /// prompt) hurts more than a longer tool list: the provider is omitted and the
  /// full registry reaches every prompt.
  final bool filterTools;

  /// Whether to inject the family's reasoning channel (Gemma's `<|think|>`
  /// marker) ahead of each answer.
  ///
  /// `true` (default) lets a capable model reason before responding. Set
  /// `false` for an edge model (e.g. E2B) where the thinking pass burns scarce
  /// decode tokens before any user-visible output for little quality gain. The
  /// flag is a no-op for formats whose `ChatFormat.supportsThinking` is false.
  final bool enableThinking;

  /// Which inference engine runs this spec. Today only `'llama'` exists.
  ///
  /// When a second engine lands (LiteRT-LM, Apple Foundation Models), this
  /// becomes the dispatch key for an `InferenceEngine` abstraction —
  /// `canRun(spec)` / `createClient(spec)` — yielding a `ChatClient` per
  /// spec. A token-in/token-out engine reuses [format]; a message-native
  /// engine (Apple FM) implements `ChatClient` directly and ignores it.
  /// Deliberately not built yet: with one engine there is nothing to
  /// dispatch.
  final String engineId;
}
