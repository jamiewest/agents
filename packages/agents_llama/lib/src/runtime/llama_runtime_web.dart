// ignore_for_file: avoid_web_libraries_in_flutter, use_null_aware_elements

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../models/model_spec.dart';
import 'gguf_split.dart';
import 'llama_runtime_api.dart';
import 'stop_sequence_filter.dart';

const String _wasmAssetBase = 'assets/packages/agents_llama/lib/assets/wasm';
const int _maxWebModelBytes = 0x7fffffff;

/// OPFS directory holding oversized models downloaded by this runtime.
///
/// Models at or under the wasm32 per-file limit go through wllama's own
/// URL cache instead; only files that must be staged as client-side
/// splits land here (keyed by URL, reused across sessions).
const String _largeModelCacheDir = 'agents_llama_large_models';

/// Creates the wllama runtime for Flutter web.
LlamaRuntime createLlamaRuntime() => WebLlamaRuntime();

/// Loads GGUF models through a page-provided wllama JavaScript constructor.
///
/// The page must expose `globalThis.Wllama` from `@wllama/wllama` before a
/// model is loaded. The package provides the wasm asset paths expected by that
/// constructor.
final class WebLlamaRuntime implements LlamaRuntime {
  @override
  bool get supportsMultiThreading => web.window.crossOriginIsolated;

  @override
  Future<LlamaSession> loadModel(
    ModelSpec spec, {
    String? localPath,
    String? localMmprojPath,
    String? localDraftPath,
    LlamaLoadProgress? onProgress,
  }) async {
    final selectedDraftPath = localDraftPath?.trim();
    if (spec.draftUrl != null ||
        (selectedDraftPath != null && selectedDraftPath.isNotEmpty)) {
      throw UnsupportedError(
        'Speculative-decoding draft (MTP) models are not supported by the '
        'web local llama runtime: wllama cannot stage a second GGUF for '
        'spec_draft_model. Remove the draft artifact or run the native app.',
      );
    }

    final constructor = web.window.getProperty<JSFunction?>('Wllama'.toJS);
    if (constructor == null) {
      throw StateError(
        'Wllama is not available on globalThis. Load @wllama/wllama before '
        'creating a local llama web session.',
      );
    }

    // wllama 3.x ships one unified wasm (threading is chosen at runtime) and
    // reads only the 'default' key from this map; the per-thread-count paths
    // of wllama 1.x/2.x are gone.
    final instance = constructor.callAsConstructor<JSObject>(
      <String, String>{'default': '$_wasmAssetBase/wllama.wasm'}.jsify(),
    );

    final selectedLocalPath = localPath?.trim();
    final selectedMmprojPath = localMmprojPath?.trim();
    if (selectedLocalPath != null && selectedLocalPath.isNotEmpty) {
      final blobs = <web.Blob>[
        ...await _asLoadableParts(await _fetchBlob(selectedLocalPath)),
      ];
      if (selectedMmprojPath != null && selectedMmprojPath.isNotEmpty) {
        // wllama identifies the projector blob by its GGUF metadata
        // (general.architecture == "clip"), so order does not matter.
        blobs.add(await _fetchBlob(selectedMmprojPath));
      }
      await _loadFromBlobs(instance, blobs, spec);
      return _WebLlamaSession(instance, spec.contextSize);
    }

    // A single file of 2 GiB or more cannot be staged in wasm32, so it
    // is downloaded once into OPFS and split client-side into the same
    // multi-file layout `llama-gguf-split` would produce. Smaller
    // models keep wllama's own URL download cache.
    final contentLength = await _fetchContentLength(spec.modelUrl);
    if (contentLength != null && contentLength > _maxWebModelBytes) {
      final model = await _cachedLargeModel(
        spec.modelUrl,
        contentLength,
        onProgress,
      );
      final blobs = <web.Blob>[
        ...await _asLoadableParts(model),
        if (spec.mmprojUrl != null) await _fetchBlob(spec.mmprojUrl.toString()),
      ];
      await _loadFromBlobs(instance, blobs, spec);
      return _WebLlamaSession(instance, spec.contextSize);
    }

    await instance.callMethodVarArgs<JSPromise<JSAny?>>(
      'loadModelFromUrl'.toJS,
      [
        <String, Object?>{
          'url': spec.modelUrl.toString(),
          if (spec.mmprojUrl != null) 'mmprojUrl': spec.mmprojUrl.toString(),
        }.jsify(),
        <String, Object?>{
          'n_ctx': spec.contextSize,
          'n_gpu_layers': spec.gpuLayers,
          'useCache': true,
          if (onProgress != null)
            'progressCallback': _createProgressCallback(onProgress),
        }.jsify(),
      ],
    ).toDart;

    return _WebLlamaSession(instance, spec.contextSize);
  }

  static Future<void> _loadFromBlobs(
    JSObject instance,
    List<web.Blob> blobs,
    ModelSpec spec,
  ) async {
    await instance.callMethodVarArgs<JSPromise<JSAny?>>('loadModel'.toJS, [
      blobs.toJS,
      <String, Object?>{
        'n_ctx': spec.contextSize,
        'n_gpu_layers': spec.gpuLayers,
      }.jsify(),
    ]).toDart;
  }

  /// Returns [model] as the blob list wllama can stage: the blob itself
  /// when it fits the wasm32 per-file limit, otherwise GGUF splits
  /// composed of a rewritten header plus zero-copy slices of [model].
  static Future<List<web.Blob>> _asLoadableParts(web.Blob model) async {
    if (model.size <= _maxWebModelBytes) return [model];

    // The header (metadata plus tensor infos) must be parsed whole; its
    // size is unknown up front, so read a growing prefix. Tokenizer
    // metadata dominates and rarely passes a few tens of megabytes.
    var prefixLength = 8 * 1024 * 1024;
    const maxPrefixLength = 1024 * 1024 * 1024;
    while (true) {
      prefixLength = math.min(prefixLength, model.size);
      final prefix = (await model.slice(0, prefixLength).arrayBuffer().toDart)
          .toDart
          .asUint8List();
      final result = planGgufSplit(
        headerPrefix: prefix,
        totalBytes: model.size,
      );
      switch (result) {
        case GgufSplitPlan(:final parts):
          return [
            for (final part in parts)
              web.Blob(
                [
                  part.headerBytes.toJS,
                  model.slice(part.dataStart, part.dataEnd),
                ].toJS,
              ),
          ];
        case GgufSplitNeedsLargerPrefix():
          if (prefixLength >= model.size || prefixLength >= maxPrefixLength) {
            throw UnsupportedError(
              'The GGUF header could not be parsed for client-side '
              'splitting. Use a pre-split GGUF (a file ending in '
              '-00001-of-00002.gguf) or run the native app.',
            );
          }
          prefixLength *= 8;
        case GgufSplitUnsupported(:final reason):
          throw UnsupportedError(
            'This ${_formatBytes(model.size)} GGUF cannot be loaded on '
            'web: $reason Use a pre-split GGUF (a file ending in '
            '-00001-of-00002.gguf) or run the native app.',
          );
      }
    }
  }

  /// Downloads an oversized model into OPFS (reusing a previous copy of
  /// the same size) and returns it as a disk-backed [web.Blob].
  ///
  /// Falls back to an in-memory fetch when OPFS is unavailable — the
  /// model then loads but is re-downloaded next session.
  static Future<web.Blob> _cachedLargeModel(
    Uri modelUrl,
    int contentLength,
    LlamaLoadProgress? onProgress,
  ) async {
    final web.FileSystemDirectoryHandle cacheDir;
    try {
      final opfs = await web.window.navigator.storage.getDirectory().toDart;
      cacheDir = await opfs
          .getDirectoryHandle(
            _largeModelCacheDir,
            web.FileSystemGetDirectoryOptions(create: true),
          )
          .toDart;
    } catch (_) {
      final response = await _fetchOk(modelUrl.toString());
      return response.blob().toDart;
    }

    final name = _cacheFileName(modelUrl);
    try {
      final existing = await cacheDir.getFileHandle(name).toDart;
      final file = await existing.getFile().toDart;
      if (file.size == contentLength) return file;
    } catch (_) {
      // Nothing cached yet.
    }

    final handle = await cacheDir
        .getFileHandle(name, web.FileSystemGetFileOptions(create: true))
        .toDart;
    final writable = await handle.createWritable().toDart;
    try {
      final response = await _fetchOk(modelUrl.toString());
      final body = response.body;
      if (body == null) {
        throw StateError('The model download returned no body.');
      }
      final reader = body.getReader() as web.ReadableStreamDefaultReader;
      var received = 0;
      while (true) {
        final chunk = await reader.read().toDart;
        if (chunk.done) break;
        final value = chunk.value as JSObject;
        received += value.getProperty<JSNumber>('byteLength'.toJS).toDartInt;
        await writable.write(value).toDart;
        onProgress?.call((received / contentLength).clamp(0, 1).toDouble());
      }
    } finally {
      await writable.close().toDart;
    }

    // Ask the browser not to evict the copy under storage pressure.
    try {
      await web.window.navigator.storage.persist().toDart;
    } catch (_) {
      // Best-effort only.
    }
    return (await handle.getFile().toDart);
  }

  /// A stable OPFS-safe cache name for [modelUrl].
  static String _cacheFileName(Uri modelUrl) {
    final url = modelUrl.toString();
    // djb2 kept within 32 bits; the multiplier is small enough that the
    // intermediate stays exact in JS doubles on the web backend.
    var hash = 5381;
    for (final unit in url.codeUnits) {
      hash = (hash * 33 + unit) & 0xffffffff;
    }
    final tail = modelUrl.pathSegments.isEmpty
        ? 'model'
        : modelUrl.pathSegments.last;
    var safeTail = tail.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    if (safeTail.length > 64) safeTail = safeTail.substring(0, 64);
    return '${hash.toRadixString(16)}-$safeTail';
  }

  static Future<web.Response> _fetchOk(String url) async {
    final response = await web.window
        .callMethodVarArgs<JSPromise<web.Response>>('fetch'.toJS, [url.toJS])
        .toDart;
    if (!response.ok) {
      throw StateError(
        'The model download failed with HTTP ${response.status}.',
      );
    }
    return response;
  }

  static Future<web.Blob> _fetchBlob(String objectUrl) async {
    final response = await _fetchOk(objectUrl);
    return response.blob().toDart;
  }

  static Future<int?> _fetchContentLength(Uri modelUrl) async {
    try {
      final response = await web.window.callMethodVarArgs<JSPromise<JSObject>>(
        'fetch'.toJS,
        [
          modelUrl.toString().toJS,
          <String, Object?>{'method': 'HEAD'}.jsify(),
        ],
      ).toDart;
      final headers = response.getProperty<JSObject?>('headers'.toJS);
      final contentLength = headers
          ?.callMethod<JSString?>('get'.toJS, 'content-length'.toJS)
          ?.toDart;
      return contentLength == null ? null : int.tryParse(contentLength);
    } on UnsupportedError {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  static String _formatBytes(int bytes) {
    final gibibytes = bytes / (1024 * 1024 * 1024);
    return '${gibibytes.toStringAsFixed(2)} GiB';
  }

  static JSFunction _createProgressCallback(
    LlamaLoadProgress onProgress,
  ) => ((JSObject progress) {
    final loaded = progress.getProperty<JSNumber?>('loaded'.toJS)?.toDartDouble;
    final total = progress.getProperty<JSNumber?>('total'.toJS)?.toDartDouble;
    if (loaded == null || total == null || total <= 0) return;
    onProgress((loaded / total).clamp(0, 1).toDouble());
  }).toJS;
}

final class _WebLlamaSession implements LlamaSession {
  _WebLlamaSession(this._wllama, this._contextSize);

  final JSObject _wllama;

  /// The `n_ctx` the model was loaded with. Used to fail fast when a prompt
  /// cannot fit (wllama's prefill hangs rather than erroring) and to clamp
  /// `max_tokens` so prompt + output stays within the window.
  final int _contextSize;

  /// Pessimistic characters-per-token ratio for the token estimate below.
  /// Real tokenization varies, but ~3 chars/token over-counts for English
  /// prose, which is what we want for a conservative "does it fit" guard.
  static const double _charsPerToken = 3;

  JSObject? _abortController;

  @override
  Stream<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.8,
    int? topK,
    double? topP,
    int? seed,
    List<String> stopSequences = const <String>[],
    List<Uint8List>? media,
    List<LlamaChatTurn>? turns,
    LlamaStatsCallback? onStats,
  }) {
    final isMediaTurn = media != null && media.isNotEmpty;
    if (isMediaTurn) {
      if (turns == null) {
        throw UnsupportedError(
          'Media input on the web local llama runtime requires structured '
          'chat turns.',
        );
      }
      final hasImage = turns.any((turn) => turn.images.isNotEmpty);
      final hasAudio = turns.any((turn) => turn.audio.isNotEmpty);
      if (hasImage && !_supportsModality('image')) {
        throw StateError(
          'The loaded local llama model has no vision projector. Configure a '
          'projector (mmproj) GGUF for this model to send images.',
        );
      }
      if (hasAudio && !_supportsModality('audio')) {
        throw StateError(
          'The loaded local llama model has no audio projector. Configure an '
          'audio-capable projector (mmproj) GGUF for this model to send audio.',
        );
      }
    }

    final controller = StreamController<String>();

    // A prompt longer than the context window makes wllama's prefill hang
    // indefinitely instead of erroring. Estimate prompt tokens pessimistically
    // and fail fast with an actionable message; also clamp `max_tokens` so the
    // prompt plus the requested output stays within `n_ctx`. Skip for media
    // turns, whose token cost is dominated by mtmd image/audio tokens we can't
    // size from the text here.
    var effectiveMaxTokens = maxTokens;
    if (!isMediaTurn) {
      final estimatedPromptTokens = (prompt.length / _charsPerToken).ceil();
      if (estimatedPromptTokens >= _contextSize) {
        controller
          ..addError(
            StateError(
              'The prompt (~$estimatedPromptTokens tokens) does not fit the '
              'model context ($_contextSize tokens). Increase the model '
              'context size or shorten the prompt (e.g. fewer tools).',
            ),
          )
          ..close();
        return StopSequenceFilter(stopSequences).bind(controller.stream);
      }
      final room = _contextSize - estimatedPromptTokens;
      effectiveMaxTokens = maxTokens.clamp(1, room);
    }

    final abortController = _createAbortController();
    _abortController = abortController;
    final abortSignal = abortController?.getProperty<JSAny?>('signal'.toJS);

    final options =
        <String, Object?>{
              if (isMediaTurn)
                'messages': _chatMessages(turns!)
              else
                'prompt': prompt,
              'stream': true,
              'max_tokens': effectiveMaxTokens,
              'temp': temperature,
              if (topK != null) 'top_k': topK,
              if (topP != null) 'top_p': topP,
              if (seed != null) 'seed': seed,
              if (abortSignal != null) 'abortSignal': abortSignal,
            }.jsify()
            as JSObject;
    // Token accounting: wllama invokes onData once per generated token, and
    // its tokenizer sizes the prompt. The count runs concurrently with the
    // generation and is best-effort — a tokenize failure only skips stats,
    // never the generation. Media turns approximate: the count covers the
    // rendered text prompt, not mtmd image/audio tokens.
    var generatedCount = 0;
    final promptTokenCount = onStats == null
        ? Future<int?>.value()
        : _countPromptTokens(prompt);

    options['onData'] = ((JSObject chunk) {
      generatedCount++;
      final text = isMediaTurn ? _chatChunkText(chunk) : _chunkText(chunk);
      if (text.isNotEmpty && !controller.isClosed) {
        controller.add(text);
      }
    }).toJS;

    final method = isMediaTurn ? 'createChatCompletion' : 'createCompletion';
    unawaited(
      _wllama
          .callMethod<JSPromise<JSAny?>>(method.toJS, options)
          .toDart
          .then((_) async {
            if (onStats != null) {
              final promptTokens = await promptTokenCount;
              if (promptTokens != null) {
                onStats(
                  LlamaGenerationStats(
                    promptTokenCount: promptTokens,
                    cachedTokenCount: 0,
                    generatedTokenCount: generatedCount,
                  ),
                );
              }
            }
            if (!controller.isClosed) controller.close();
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller
                ..addError(error, stackTrace)
                ..close();
            }
          }),
    );

    return StopSequenceFilter(stopSequences).bind(controller.stream);
  }

  /// Sizes [prompt] with wllama's tokenizer; null when tokenization fails.
  Future<int?> _countPromptTokens(String prompt) async {
    try {
      final result = await _wllama
          .callMethod<JSPromise<JSAny?>>('tokenize'.toJS, prompt.toJS)
          .toDart;
      final tokens = result as JSObject?;
      return tokens?.getProperty<JSNumber?>('length'.toJS)?.toDartInt;
    } on Object {
      return null;
    }
  }

  /// Whether wllama reports the loaded model accepts [modality]
  /// (`'image'` or `'audio'`) — i.e. an appropriate mmproj is loaded.
  bool _supportsModality(String modality) =>
      _wllama
          .callMethod<JSBoolean?>('supportInputModality'.toJS, modality.toJS)
          ?.toDart ??
      false;

  /// Converts [turns] to wllama's OAI-style chat messages. Turns with media
  /// carry `{type: 'image'|'audio', data: <bytes>}` parts (wllama accepts any
  /// typed array where its types say `ArrayBuffer`); text-only turns use plain
  /// string content.
  static List<Map<String, Object?>> _chatMessages(List<LlamaChatTurn> turns) =>
      <Map<String, Object?>>[
        for (final turn in turns)
          <String, Object?>{
            'role': turn.role,
            'content': turn.images.isEmpty && turn.audio.isEmpty
                ? turn.text
                : <Map<String, Object?>>[
                    for (final image in turn.images)
                      <String, Object?>{'type': 'image', 'data': image},
                    for (final clip in turn.audio)
                      <String, Object?>{'type': 'audio', 'data': clip},
                    if (turn.text.isNotEmpty)
                      <String, Object?>{'type': 'text', 'text': turn.text},
                  ],
          },
      ];

  @override
  Future<void> cancel() async {
    final abortController = _abortController;
    if (abortController != null) {
      abortController.callMethod<JSAny?>('abort'.toJS);
    }
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _wllama.callMethod<JSPromise<JSAny?>>('exit'.toJS).toDart;
  }

  static JSObject? _createAbortController() {
    final constructor = web.window.getProperty<JSFunction?>(
      'AbortController'.toJS,
    );
    if (constructor == null) return null;
    return constructor.callAsConstructor<JSObject>();
  }

  static String _chunkText(JSObject chunk) {
    final first = _firstChoice(chunk);
    if (first == null) return '';
    return first.getProperty<JSString?>('text'.toJS)?.toDart ?? '';
  }

  static String _chatChunkText(JSObject chunk) {
    final first = _firstChoice(chunk);
    if (first == null) return '';
    final delta = first.getProperty<JSObject?>('delta'.toJS);
    if (delta == null) return '';
    return delta.getProperty<JSString?>('content'.toJS)?.toDart ?? '';
  }

  static JSObject? _firstChoice(JSObject chunk) {
    final choices = chunk.getProperty<JSObject?>('choices'.toJS);
    return choices?.getProperty<JSObject?>('0'.toJS);
  }
}
