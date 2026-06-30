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
  Future<LlamaSession> loadModel(
    ModelSpec spec, {
    String? localPath,
    LlamaLoadProgress? onProgress,
  }) async {
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
    if (selectedLocalPath != null && selectedLocalPath.isNotEmpty) {
      final blob = await _fetchBlob(selectedLocalPath);
      await instance.callMethodVarArgs<JSPromise<JSAny?>>('loadModel'.toJS, [
        <web.Blob>[blob].toJS,
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
          spec.modelUrl.toString().toJS,
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

    return _WebLlamaSession(instance);
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
  _WebLlamaSession(this._wllama);

  final JSObject _wllama;
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
  }) {
    if (images != null && images.isNotEmpty) {
      throw UnsupportedError(
        'Image input is not supported by the web local llama runtime.',
      );
    }

    final controller = StreamController<String>();
    final abortController = _createAbortController();
    _abortController = abortController;
    final abortSignal = abortController?.getProperty<JSAny?>('signal'.toJS);

    final options =
        <String, Object?>{
              'prompt': prompt,
              'stream': true,
              'max_tokens': maxTokens,
              'temp': temperature,
              if (topK != null) 'top_k': topK,
              if (topP != null) 'top_p': topP,
              if (seed != null) 'seed': seed,
              if (abortSignal != null) 'abortSignal': abortSignal,
            }.jsify()
            as JSObject;
    options['onData'] = ((JSObject chunk) {
      final text = _chunkText(chunk);
      if (text.isNotEmpty && !controller.isClosed) {
        controller.add(text);
      }
    }).toJS;

    unawaited(
      _wllama
          .callMethod<JSPromise<JSAny?>>('createCompletion'.toJS, options)
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
    final choices = chunk.getProperty<JSObject?>('choices'.toJS);
    if (choices == null) return '';
    final first = choices.getProperty<JSObject?>('0'.toJS);
    if (first == null) return '';
    return first.getProperty<JSString?>('text'.toJS)?.toDart ?? '';
  }
}
