import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';

import 'llama_worker.dart';
import 'messages.g.dart';

/// Token accounting for one completed generation run.
class LlamaGenerationStats {
  /// Creates a [LlamaGenerationStats].
  const LlamaGenerationStats({
    required this.promptTokenCount,
    required this.cachedTokenCount,
    required this.generatedTokenCount,
  });

  /// Prompt tokens fed to the model (including the reused prefix).
  final int promptTokenCount;

  /// Prompt tokens served from the reused KV-cache prefix.
  final int cachedTokenCount;

  /// Tokens generated.
  final int generatedTokenCount;
}

/// Owns the worker isolate and routes commands/replies between it and the
/// main isolate. One instance backs a single [LlamaFlutter] facade.
class LlamaIsolate {
  final ReceivePort _fromWorker = ReceivePort();
  final Completer<void> _ready = Completer<void>();
  final Map<int, Completer<int>> _loads = <int, Completer<int>>{};
  final Map<int, Completer<int>> _stateOps = <int, Completer<int>>{};
  final Map<int, StreamController<String>> _generations =
      <int, StreamController<String>>{};
  final Map<int, void Function(LlamaGenerationStats)> _statsCallbacks =
      <int, void Function(LlamaGenerationStats)>{};

  /// Generations requested while the same session's previous run was still in
  /// flight, started once that run's `done` event arrives. Tokens carry only a
  /// sessionId, so starting the new run earlier would route the old run's
  /// remaining events (including its `done`, which closes the stream) into the
  /// new controller.
  final Map<int, _PendingGeneration> _pending = <int, _PendingGeneration>{};

  SendPort? _commands;
  StreamSubscription<TokenEvent>? _tokens;
  int _nextRequestId = 1;
  bool _started = false;

  /// Spawns the worker and waits for its handshake.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    final token = RootIsolateToken.instance;
    if (token == null) {
      throw StateError(
        'RootIsolateToken unavailable; call from the root isolate.',
      );
    }

    _fromWorker.listen(_handleMessage);
    await Isolate.spawn(
      llamaWorkerMain,
      WorkerInit(token, _fromWorker.sendPort),
    );
    await _ready.future;

    // The token EventChannel must be listened to on the root isolate; a
    // background isolate cannot register a platform message handler. Native
    // generation runs on the worker's command calls, but its TokenEvents are
    // delivered here and routed to the per-session controllers.
    _tokens = streamTokens().listen(_handleTokenEvent);
  }

  /// Loads a model and resolves to its session id.
  Future<int> loadModel(ModelLoadRequest request) async {
    final requestId = _nextRequestId++;
    final completer = Completer<int>();
    _loads[requestId] = completer;
    _commands!.send(LoadCommand(requestId, request));
    return completer.future;
  }

  /// Starts generation and returns a stream of decoded token text.
  ///
  /// If the session's previous run is still in flight it is cancelled, and
  /// the new run starts only once its `done` event arrives (see [_pending]).
  ///
  /// [onStats] is invoked once with the run's token accounting when the
  /// native side reports it on the `done` event.
  Stream<String> generate(
    GenerationRequest request, {
    void Function(LlamaGenerationStats)? onStats,
  }) {
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onCancel: () {
        if (_pending[request.sessionId]?.controller == controller) {
          _pending.remove(request.sessionId);
        } else {
          _commands!.send(CancelCommand(request.sessionId));
        }
      },
    );

    if (_generations.containsKey(request.sessionId)) {
      _pending.remove(request.sessionId)?.controller.close();
      _pending[request.sessionId] = (
        request: request,
        controller: controller,
        onStats: onStats,
      );
      _commands!.send(CancelCommand(request.sessionId));
    } else {
      _generations[request.sessionId] = controller;
      if (onStats != null) _statsCallbacks[request.sessionId] = onStats;
      _commands!.send(GenerateCommand(request));
    }
    return controller.stream;
  }

  Future<void> cancel(int sessionId) async {
    _commands!.send(CancelCommand(sessionId));
  }

  /// Saves (or, with `save: false`, restores) a session's KV-cache state.
  ///
  /// Resolves to the snapshot's token count. Worker commands are serviced in
  /// order, so a state operation issued before a [generate] runs before it.
  Future<int> sessionState(int sessionId, String path, {required bool save}) {
    final requestId = _nextRequestId++;
    final completer = Completer<int>();
    _stateOps[requestId] = completer;
    _commands!.send(StateCommand(requestId, sessionId, path, save: save));
    return completer.future;
  }

  Future<void> disposeSession(int sessionId) async {
    _generations.remove(sessionId)?.close();
    _statsCallbacks.remove(sessionId);
    _pending.remove(sessionId)?.controller.close();
    _commands!.send(DisposeCommand(sessionId));
  }

  /// Shuts the worker down and releases all stream controllers.
  Future<void> dispose() async {
    await _tokens?.cancel();
    _commands?.send(const ShutdownCommand());
    for (final controller in _generations.values) {
      await controller.close();
    }
    _generations.clear();
    for (final pending in _pending.values) {
      await pending.controller.close();
    }
    _pending.clear();
    _fromWorker.close();
  }

  void _handleMessage(Object? message) {
    switch (message) {
      case SendPort commandPort:
        _commands = commandPort;
        if (!_ready.isCompleted) _ready.complete();
      case LoadResult(:final requestId, :final sessionId, :final error):
        final completer = _loads.remove(requestId);
        if (completer == null) return;
        if (error != null) {
          completer.completeError(LlamaException(error));
        } else {
          completer.complete(sessionId);
        }
      case StateResult(:final requestId, :final tokenCount, :final error):
        final completer = _stateOps.remove(requestId);
        if (completer == null) return;
        if (error != null) {
          completer.completeError(LlamaException(error));
        } else {
          completer.complete(tokenCount);
        }
    }
  }

  /// Routes a native token event to the controller for its session.
  void _handleTokenEvent(TokenEvent event) {
    final controller = _generations[event.sessionId];
    if (controller == null) return;
    if (event.error != null) {
      controller.addError(LlamaException(event.error!));
    } else if (event.text != null) {
      controller.add(event.text!);
    }
    if (event.done) {
      _generations.remove(event.sessionId);
      final onStats = _statsCallbacks.remove(event.sessionId);
      if (onStats != null &&
          event.error == null &&
          event.promptTokenCount != null &&
          event.generatedTokenCount != null) {
        onStats(
          LlamaGenerationStats(
            promptTokenCount: event.promptTokenCount!,
            cachedTokenCount: event.cachedTokenCount ?? 0,
            generatedTokenCount: event.generatedTokenCount!,
          ),
        );
      }
      controller.close();
      final pending = _pending.remove(event.sessionId);
      if (pending != null) {
        _generations[event.sessionId] = pending.controller;
        if (pending.onStats != null) {
          _statsCallbacks[event.sessionId] = pending.onStats!;
        }
        _commands!.send(GenerateCommand(pending.request));
      }
    }
  }
}

/// A generation waiting for the same session's previous run to finish.
typedef _PendingGeneration = ({
  GenerationRequest request,
  StreamController<String> controller,
  void Function(LlamaGenerationStats)? onStats,
});

/// Thrown when native model loading or generation fails.
class LlamaException implements Exception {
  LlamaException(this.message);
  final String message;

  @override
  String toString() => 'LlamaException: $message';
}
