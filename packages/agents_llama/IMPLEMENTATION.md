# Implementation Spec: `agents_llama` Local Model Support

This is an executable spec for an implementing agent. Follow the phases in
order. Each phase has explicit acceptance checks. Where a choice existed it has
already been resolved into a directive — do not re-open it. Verify the few items
marked **VERIFY** against the actual code/library at the moment you touch them
(facts drift), but do not change the architecture.

## Goal

Create `packages/agents_llama`: one Dart `ChatClient` path for local GGUF models
that runs on **iOS, macOS, and web** behind a conditional-import runtime seam,
and wire it into the `agents_flutter` configured-agents example so a user can add
a "Local llama" source, give a GGUF URL, and chat through the existing UI.
`agents_flutter` must **not** depend on `agents_llama`.

## Source material (port from these — do not invent)

Two existing implementations are the source of truth. Read them before writing.

**Native runtime — `/Users/jamie/Developer/flutter_application_7/packages/llama_flutter/`**
Public API (`lib/llama_flutter.dart`): `LlamaFlutter`, `LlamaSession`,
`LlamaException`.
- `LlamaFlutter.loadModel(String path, {int contextSize = 4096, int gpuLayers = 999, String? mmprojPath, String? draftModelPath, int draftGpuLayers = 999, int maxDraftTokens = 8}) → Future<LlamaSession>`
- `LlamaSession.generate(String prompt, {int maxTokens = 256, double temperature = 0.8, int? topK, double? topP, int? seed, List<String> stopSequences = const [], List<Uint8List>? images}) → Stream<String>`
- `LlamaSession.cancel() / saveState / loadState / dispose`
- Internals to copy verbatim: `lib/src/llama_isolate.dart`,
  `lib/src/llama_worker.dart`, `lib/src/messages.g.dart`, `pigeons/messages.dart`,
  `darwin/` (Classes/*.swift, LlamaExtShim.{h,cpp}, podspec,
  Frameworks/llama.xcframework), `scripts/build_llama_xcframework.sh`.
  The Dart side uses `dart:isolate` + `BackgroundIsolateBinaryMessenger`
  (web-incompatible — this is why the seam below exists).
  Native `generate` already does stop-sequence stripping and UTF-8 reassembly.

**Chat layer — `/Users/jamie/Developer/atlas_app/`**
- `lib/llm/chat_format.dart` — `abstract interface class ChatFormat`:
  `bool get supportsThinking`,
  `RenderedPrompt render(Iterable<ChatMessage> messages, {Iterable<AIFunctionDeclaration> tools, bool enableThinking})`,
  `Stream<ChatResponseUpdate> decode(Stream<String> tokens)`.
- `lib/llm/llama/llama_chat_client.dart` — `class LlamaChatClient extends ChatClient`
  (ctor: `sessionProvider`, `format`, `contextSize`, `sampling`, `inspector`,
  `isThinkingEnabled`). Pipeline: `messagesWithInstructions` → `format.render` →
  `session.generate(prompt.text, ... stopSequences, images)` → `format.decode`.
- `lib/llm/llama/llama_chat_client_factory.dart` — `createLlamaChatClient({required ModelSpec spec, required SessionProvider sessionProvider, int? contextSizeOverride, SamplingDefaults? samplingOverride, bool Function()? isThinkingEnabled, PromptInspector? inspector})`.
  `SessionProvider` is `typedef () → Future<LlamaSession>` (lazy load).
- `lib/llm/gemma/` — `gemma_chat_format.dart` (`GemmaChatFormat implements ChatFormat`,
  `supportsThinking == true`), `gemma_chat_template.dart` (faithful port of
  Gemma `chat_template.jinja`; **deliberately omits BOS**; control tokens +
  `stopSequences = ['<turn|>', '<|tool_response>']`; emits `<__media__>` for
  images), `gemma_stream_decoder.dart` (splits raw tokens → `TextReasoningContent`
  / `TextContent` / `FunctionCallContent`, prose & tool-calls in separate updates).
- `lib/models/model_spec.dart` — `class ModelSpec` (id, displayName, modelUrl,
  mmprojUrl, draftUrl, contextSize, gpuLayers, `ChatFormat format`,
  `SamplingDefaults sampling`, filterTools, enableThinking, engineId) and
  `class SamplingDefaults` (maxTokens=512, temperature=1.0, topK?, topP?, seed?).
- Reference for native model acquisition flow:
  `lib/services/llama_model_service.dart` + `lib/services/model_controller.dart`.

> The original plan named `flutter_application_7` for the chat layer (wrong — it
> is `atlas_app`) and listed nonexistent types `LlamaRuntime`,
> `LlamaModelSession`, `LlamaModelSpec`. Real names: `LlamaFlutter`,
> `LlamaSession`, `ModelSpec`. The cross-platform runtime/session abstraction is
> **new code** (named `LlamaRuntime`/`LlamaSession` interfaces in `agents_llama`).

## Target framework facts (verified)

- `ChatClient` is `package:extensions/ai.dart`, `abstract class ChatClient implements Disposable`:
  `Future<ChatResponse> getResponse({required Iterable<ChatMessage> messages, ChatOptions? options, CancellationToken? cancellationToken})`,
  `Stream<ChatResponseUpdate> getStreamingResponse({...})`, `T? getService<T>({Object? key})`.
- Root pub workspace: `/Users/jamie/Developer/agents/pubspec.yaml` has
  `workspace: [packages/agents, packages/agents_flutter]` and a
  `dependency_overrides: extensions: path: ../extensions/packages/extensions`.
  `packages/agents_llama/` already exists as an empty directory.
- `agents_flutter` already has a download layer to reuse on native:
  `DownloadService` + `HuggingFaceDownloader` (builds
  `huggingface.co/{repo}/resolve/{revision}/{file}`) under
  `packages/agents_flutter/lib/src/.../download/` + `huggingface/`. **VERIFY**
  exact paths/symbols before calling them.

## wllama web API (verified against `src/wllama.ts` @ master)

- `new Wllama(pathConfig: AssetsPathConfig, wllamaConfig?: WllamaConfig)`.
  `AssetsPathConfig = { default: string; 'single-thread/wllama.wasm'?: string; 'multi-thread/wllama.wasm'?: string }`.
- `loadModelFromUrl(urlOrSource, params: LoadModelParams & DownloadOptions & { useCache?: boolean })`;
  `LoadModelParams` includes `n_ctx`, `n_gpu_layers`, `n_threads`. Split GGUF:
  pass the first chunk URL.
- `loadModelFromHF({ repo, file }, params)`.
- Raw streaming completion (the seam target):
  `createCompletion(options: RawCompletionParams & { stream: true }) → Promise<AsyncIterable<RawCompletionChunk>>`
  (also a non-stream overload and an `onData`/`onNewToken` callback overload).
  `RawCompletionParams` carries the raw prompt, `nPredict`, `sampling` (`temp`,
  `top_k`, `top_p`, `seed`), `useCache`.
- **VERIFY at impl time**: exact field names against the installed wllama
  version (3.x has drifted); whether `createCompletion` adds BOS; whether chunk
  text is already UTF-8-safe.

---

## Phase 1 — Create the package skeleton

1. Create `packages/agents_llama/pubspec.yaml` modeled on
   `packages/agents_flutter/pubspec.yaml`: `name: agents_llama`,
   `resolution: workspace`, Flutter SDK, deps `agents`, `extensions` (path
   override inherited from root), `web`, and
   `llama_flutter: { path: ../../../flutter_application_7/packages/llama_flutter }`.
   Declare `flutter: assets: [lib/assets/wasm/]`.
2. Add `- packages/agents_llama` to `workspace:` in
   `/Users/jamie/Developer/agents/pubspec.yaml`.
3. Create the directory layout:
   ```
   lib/agents_llama.dart            # barrel (exports below)
   lib/src/models/model_spec.dart   # ModelSpec + SamplingDefaults (from atlas_app)
   lib/src/llm/chat_format.dart
   lib/src/llm/llama/llama_chat_client.dart
   lib/src/llm/llama/llama_chat_client_factory.dart
   lib/src/llm/gemma/{gemma_chat_format,gemma_chat_template,gemma_stream_decoder}.dart
   lib/src/runtime/llama_runtime.dart          # conditional-export seam
   lib/src/runtime/llama_runtime_api.dart      # LlamaRuntime + LlamaSession interfaces
   lib/src/runtime/llama_runtime_native.dart
   lib/src/runtime/llama_runtime_web.dart
   lib/src/runtime/llama_runtime_stub.dart
   lib/src/runtime/stop_sequence_filter.dart   # shared helper
   lib/assets/wasm/                            # bundled wllama wasm
   ```
4. Copy the Gemma fixtures/tests dir from atlas_app if present (template is
   fixture-validated) so the port stays byte-faithful.

**Acceptance:** `dart pub get` at root resolves; `dart analyze packages/agents_llama`
runs (failures from unported files are expected at this stage).

## Phase 2 — Define the cross-platform runtime seam (new code)

1. `llama_runtime_api.dart` — runtime-agnostic interfaces:
   - `abstract interface class LlamaSession { Stream<String> generate(String prompt, {int maxTokens, double temperature, int? topK, double? topP, int? seed, List<String> stopSequences, List<Uint8List>? images}); Future<void> cancel(); Future<void> dispose(); }`
   - `abstract interface class LlamaRuntime { Future<LlamaSession> loadModel(ModelSpec spec, {String? localPath}); }`
   - Contract: `generate` MUST yield text with stop sequences removed and
     terminate at the first stop sequence (matches native behavior the Gemma
     decoder relies on).
2. `llama_runtime.dart` — conditional export:
   ```dart
   export 'llama_runtime_stub.dart'
       if (dart.library.io) 'llama_runtime_native.dart'
       if (dart.library.js_interop) 'llama_runtime_web.dart';
   ```
   Each variant exposes a top-level `LlamaRuntime createLlamaRuntime()`.
3. `llama_runtime_native.dart` — wraps `flutter_application_7`'s `LlamaFlutter`/
   `LlamaSession`. `loadModel` requires `localPath` (file must already be on
   disk); delegates `generate`/`cancel`/`dispose` straight through (native
   already strips stop sequences + reassembles UTF-8). This is the ONLY file
   that imports `package:llama_flutter`.
4. `llama_runtime_web.dart` — `dart:js_interop` + `package:web` bindings to
   `Wllama`. `loadModel` calls `loadModelFromUrl(spec.modelUrl, { n_ctx: contextSize, n_gpu_layers: gpuLayers, useCache: true })`
   with wasm paths from bundled assets. `generate` calls
   `createCompletion({ prompt, nPredict: maxTokens, sampling: {...}, stream: true })`,
   maps each chunk's text to the output stream, runs it through
   `StopSequenceFilter`, and **throws a clear error if `images` is non-empty**
   (no mmproj on web v1). **VERIFY** BOS: run one smoke prompt; if output is
   degraded because BOS is double/never added, set the wllama option or prepend
   BOS on this path only.
5. `llama_runtime_stub.dart` — `createLlamaRuntime()` throws
   `UnsupportedError('Local llama inference is not supported on this platform.')`.
6. `stop_sequence_filter.dart` — small pure helper that buffers a `Stream<String>`
   and truncates at the first stop sequence (used by the web adapter; unit-test
   it directly).

**Acceptance:** `flutter build web` of a trivial harness importing
`llama_runtime.dart` compiles (proves `llama_flutter`/`dart:isolate` stays out of
the web build).

## Phase 3 — Port the chat layer

1. Port `model_spec.dart`, `chat_format.dart`, the `gemma/` files, and
   `llama_chat_client.dart` + factory from atlas_app, fixing imports to
   `package:extensions/ai.dart` and the new runtime interfaces.
2. Generalize `LlamaChatClient` and `SessionProvider` to depend on the
   `agents_llama` `LlamaSession` **interface**, not the concrete native class.
3. Keep `createLlamaChatClient` signature; `SessionProvider` stays
   `typedef () → Future<LlamaSession>` so model load is lazy.
4. Barrel `lib/agents_llama.dart` exports: `LlamaChatClient`,
   `createLlamaChatClient`, `ChatFormat`, `GemmaChatFormat`, `SamplingDefaults`,
   `ModelSpec`, `LlamaRuntime`, `LlamaSession`, `createLlamaRuntime`.

**Acceptance:** `dart analyze packages/agents_llama` clean; ported atlas_app
chat/gemma unit tests pass under `flutter test`.

## Phase 4 — `agents_flutter` plumbing (no dep on `agents_llama`)

All paths under `packages/agents_flutter/lib/src/configured_agents/`.

1. `models/provider_type.dart` — add enum value `localLlama('local_llama')`. Add
   `bool get requiresApiKey` (`true` for `openAiCompatible`/`anthropic`, `false`
   for `localLlama`).
2. `models/model_config.dart` — add `final Map<String, String> settings` (default
   `const {}`). Mirror the `settings` round-trip already in
   `models/model_source_config.dart` (`toJson`: `'settings': settings`;
   `fromJson`: rebuild `Map<String,String>` from `json['settings']`).
3. `configured_chat_client_factory.dart` — add a constructor field
   `final ChatClient Function({required ModelSourceConfig source, required ModelConfig model, http.Client? httpClient})? customClientResolver;`.
   In `createChatClient`: make `apiKey` an optional named `String?`; only call
   `_validateApiKey` when `source.providerType.requiresApiKey`. Add the
   `case ProviderType.localLlama:` to the (exhaustive, no-default) switch — it
   calls `customClientResolver` and throws
   `ConfiguredAgentException('No local-model provider registered.')` if null.
4. `configured_agent_factory.dart` — gate the missing-key throw (currently
   ~lines 89–94) on `source.providerType.requiresApiKey`; pass the key (possibly
   null/empty) through to `createChatClient`.
5. `configured_agents_service_collection_extensions.dart` — `addConfiguredAgents`
   and `useConfiguredAgents` do not currently expose the chat-client factory. Add
   a param `ConfiguredChatClientFactory Function(ServiceProvider sp)? chatClientFactory`
   and thread it into the `ConfiguredAgentFactory` registration
   (`ConfiguredAgentFactory` already accepts `chatClientFactory`).

**Acceptance:** `flutter test packages/agents_flutter` passes, including new
tests: `localLlama` wire round-trip, `requiresApiKey` per provider,
`ModelConfig.settings` round-trip, local provider creation with no key, cloud
providers still throwing without a key.

## Phase 5 — Example app wiring

Under `packages/agents_flutter/example/`.

1. Add `agents_llama: { path: ../../agents_llama }` to the example pubspec; bundle
   wllama wasm (depend on the package's assets).
2. `lib/main.dart` — register a `localLlama` resolver via the new
   `useConfiguredAgents(chatClientFactory: ...)` param. The resolver:
   - reads `model.settings` (`llama.modelUrl`, `llama.contextSize`,
     `llama.gpuLayers`, `llama.format`, `llama.mmprojUrl`, `llama.draftModelUrl`),
   - builds a `ModelSpec` (format = Gemma by default via `llama.format`),
   - calls `createLlamaRuntime()` (conditional seam),
   - on **native**: fetch the GGUF to disk via the existing
     `HuggingFaceDownloader`/`DownloadService`, then `runtime.loadModel(spec, localPath: file)`;
     on **web**: `runtime.loadModel(spec)` (wllama fetches+caches),
   - returns `createLlamaChatClient(spec: spec, sessionProvider: () async => loadedSession, ...)`
     — load lazily inside the provider.
3. `lib/ui/views/configured_agents/source_editor.dart` — add "Local llama" to the
   provider dropdown; when `provider == ProviderType.localLlama`, hide the
   endpoint and API-key fields and skip the key validator (`provider.requiresApiKey`).
4. Local-model form for `localLlama` (identical on web/native): model URL
   (required), optional display name, context size (default `4096`), GPU layers
   (default `999`), optional format (default `gemma`). Persist into
   `ModelConfig.settings` under the `llama.*` keys above; `modelId` stays the
   stable configured id.

**Acceptance:** widget test confirms source/model fields show/hide for
`localLlama` vs cloud.

## Resolved directives (do not re-open)

- **Stop-sequence stripping**: native keeps its in-isolate stripping; the web
  adapter uses the shared `StopSequenceFilter`. Both satisfy the `LlamaSession`
  contract. Do not refactor native stripping.
- **UTF-8 reassembly**: native handles it; on web rely on wllama chunk text
  (VERIFY it is UTF-8-safe; if not, buffer bytes in the web adapter).
- **BOS**: default to NOT prepending (Gemma template omits it intentionally).
  VERIFY with one smoke prompt on web; correct only if degraded.
- **Images on web**: reject with a clear error in the web adapter. `mmprojUrl`/
  `draftModelUrl` are native-only in v1; web ignores them.
- **Web models > 2GB**: require split GGUF; URL points at the first chunk
  (document in the form helper text).
- **Model format**: only Gemma is wired in v1; `llama.format` other than `gemma`
  throws a clear "unsupported format" error until more formats are ported.

## Full verification (run all; all must pass)

- `dart analyze`
- `dart test` (root) and `flutter test` in `packages/agents_flutter` and
  `packages/agents_llama`
- `flutter test --platform chrome` (web-safe coverage)
- `flutter build web` for the example — proves the conditional-import seam keeps
  `llama_flutter`/`dart:isolate` out of the web compile
- `flutter build macos` for the example — native plugin wiring
- Manual: macOS run → create a no-key "Local llama" source, add a small Gemma
  GGUF URL, chat → tokens stream and decode. Chrome run with a small/split GGUF
  URL → wllama loads from cache and streams through the same UI. A cloud source
  still requires + validates an API key.
