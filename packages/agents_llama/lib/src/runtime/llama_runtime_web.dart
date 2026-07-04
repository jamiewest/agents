// ignore_for_file: avoid_web_libraries_in_flutter, use_null_aware_elements

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../models/model_spec.dart';
import 'llama_runtime_api.dart';
import 'stop_sequence_filter.dart';

const String _wasmAssetBase = 'assets/packages/agents_llama/lib/assets/wasm';
const int _maxWebModelBytes = 0x7fffffff;

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

    final instance = constructor.callAsConstructor<JSObject>(
      <String, String>{
        'default': '$_wasmAssetBase/single-thread/wllama.wasm',
        'single-thread/wllama.wasm':
            '$_wasmAssetBase/single-thread/wllama.wasm',
        'multi-thread/wllama.wasm': '$_wasmAssetBase/multi-thread/wllama.wasm',
      }.jsify(),
    );

    final selectedLocalPath = localPath?.trim();
    final selectedMmprojPath = localMmprojPath?.trim();
    if (selectedLocalPath != null && selectedLocalPath.isNotEmpty) {
      final blobs = <web.Blob>[await _fetchBlob(selectedLocalPath)];
      if (selectedMmprojPath != null && selectedMmprojPath.isNotEmpty) {
        // wllama identifies the projector blob by its GGUF metadata
        // (general.architecture == "clip"), so order does not matter.
        blobs.add(await _fetchBlob(selectedMmprojPath));
      }
      await instance.callMethodVarArgs<JSPromise<JSAny?>>('loadModel'.toJS, [
        blobs.toJS,
        <String, Object?>{
          'n_ctx': spec.contextSize,
          'n_gpu_layers': spec.gpuLayers,
        }.jsify(),
      ]).toDart;
    } else {
      await _validateModelUrlForWeb(spec.modelUrl);

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
    }

    return _WebLlamaSession(instance, spec.contextSize);
  }

  static Future<web.Blob> _fetchBlob(String objectUrl) async {
    final response = await web.window
        .callMethodVarArgs<JSPromise<web.Response>>('fetch'.toJS, [
          objectUrl.toJS,
        ])
        .toDart;
    return response.blob().toDart;
  }

  static Future<void> _validateModelUrlForWeb(Uri modelUrl) async {
    final contentLength = await _fetchContentLength(modelUrl);
    if (contentLength == null || contentLength <= _maxWebModelBytes) {
      return;
    }

    throw UnsupportedError(
      'The GGUF model at $modelUrl is ${_formatBytes(contentLength)}, which '
      'is too large for the web local llama runtime. Use a split GGUF and '
      'enter the first shard URL, for example a file ending in '
      '-00001-of-00002.gguf, or run the native app.',
    );
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
    List<Uint8List>? images,
    List<LlamaChatTurn>? turns,
  }) {
    final isImageTurn = images != null && images.isNotEmpty;
    if (isImageTurn) {
      if (!_supportsImageInput()) {
        throw StateError(
          'The loaded local llama model has no vision projector. Configure a '
          'projector (mmproj) GGUF for this model to send images.',
        );
      }
      if (turns == null) {
        throw UnsupportedError(
          'Image input on the web local llama runtime requires structured '
          'chat turns.',
        );
      }
    }

    final controller = StreamController<String>();

    // A prompt longer than the context window makes wllama's prefill hang
    // indefinitely instead of erroring. Estimate prompt tokens pessimistically
    // and fail fast with an actionable message; also clamp `max_tokens` so the
    // prompt plus the requested output stays within `n_ctx`. Skip for image
    // turns, whose token cost is dominated by mtmd image tokens we can't size
    // from the text here.
    var effectiveMaxTokens = maxTokens;
    if (!isImageTurn) {
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
              if (isImageTurn)
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
    options['onData'] = ((JSObject chunk) {
      final text = isImageTurn ? _chatChunkText(chunk) : _chunkText(chunk);
      if (text.isNotEmpty && !controller.isClosed) {
        controller.add(text);
      }
    }).toJS;

    final method = isImageTurn ? 'createChatCompletion' : 'createCompletion';
    unawaited(
      _wllama
          .callMethod<JSPromise<JSAny?>>(method.toJS, options)
          .toDart
          .then((_) {
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

  bool _supportsImageInput() =>
      _wllama
          .callMethod<JSBoolean?>('supportInputModality'.toJS, 'image'.toJS)
          ?.toDart ??
      false;

  /// Converts [turns] to wllama's OAI-style chat messages. Turns with images
  /// carry `{type: 'image', data: <bytes>}` parts (wllama accepts any typed
  /// array where its types say `ArrayBuffer`); text-only turns use plain
  /// string content.
  static List<Map<String, Object?>> _chatMessages(List<LlamaChatTurn> turns) =>
      <Map<String, Object?>>[
        for (final turn in turns)
          <String, Object?>{
            'role': turn.role,
            'content': turn.images.isEmpty
                ? turn.text
                : <Map<String, Object?>>[
                    for (final image in turn.images)
                      <String, Object?>{'type': 'image', 'data': image},
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
