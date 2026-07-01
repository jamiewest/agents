import 'dart:isolate';

import 'package:flutter/services.dart';

import 'messages.g.dart';

/// Startup payload handed to the worker isolate.
class WorkerInit {
  WorkerInit(this.token, this.sendPort);

  /// Root isolate token, required to bind platform channels in the background.
  final RootIsolateToken token;

  /// Port the worker uses to send messages back to the main isolate.
  final SendPort sendPort;
}

// --- Commands (main isolate -> worker) ---

/// Request to load a model; correlated back by [requestId].
class LoadCommand {
  LoadCommand(this.requestId, this.request);
  final int requestId;
  final ModelLoadRequest request;
}

/// Request to start generation for an already-loaded session.
class GenerateCommand {
  GenerateCommand(this.request);
  final GenerationRequest request;
}

class CancelCommand {
  CancelCommand(this.sessionId);
  final int sessionId;
}

class DisposeCommand {
  DisposeCommand(this.sessionId);
  final int sessionId;
}

/// Request to save or restore a session's KV-cache state; correlated back by
/// [requestId].
class StateCommand {
  StateCommand(this.requestId, this.sessionId, this.path, {required this.save});
  final int requestId;
  final int sessionId;
  final String path;

  /// True saves the state to [path]; false restores from it.
  final bool save;
}

/// Tears the worker down.
class ShutdownCommand {
  const ShutdownCommand();
}

// --- Replies (worker -> main isolate) ---

/// Result of a [LoadCommand]; [error] is null on success.
class LoadResult {
  LoadResult(this.requestId, this.sessionId, this.error);
  final int requestId;
  final int? sessionId;
  final String? error;
}

/// Result of a [StateCommand]; [error] is null on success and [tokenCount]
/// is the number of tokens covered by the snapshot.
class StateResult {
  StateResult(this.requestId, this.tokenCount, this.error);
  final int requestId;
  final int? tokenCount;
  final String? error;
}

/// Entry point for the worker isolate.
///
/// Binds the background binary messenger so Pigeon channels work off the root
/// isolate, then services commands and forwards the multiplexed token stream.
Future<void> llamaWorkerMain(WorkerInit init) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(init.token);
  final toMain = init.sendPort;
  final api = LlamaHostApi();

  final commands = ReceivePort();
  // Handshake: hand the command port back to the main isolate.
  toMain.send(commands.sendPort);

  // The token EventChannel is listened to on the root isolate (see
  // LlamaIsolate); a background isolate cannot register a platform message
  // handler. This isolate only issues method-channel commands.
  await for (final message in commands) {
    switch (message) {
      case LoadCommand(:final requestId, :final request):
        try {
          final sessionId = await api.loadModel(request);
          toMain.send(LoadResult(requestId, sessionId, null));
        } catch (e) {
          toMain.send(LoadResult(requestId, null, e.toString()));
        }
      case GenerateCommand(:final request):
        await api.startGeneration(request);
      case CancelCommand(:final sessionId):
        await api.cancelGeneration(sessionId);
      case DisposeCommand(:final sessionId):
        await api.disposeSession(sessionId);
      case StateCommand(
        :final requestId,
        :final sessionId,
        :final path,
        :final save,
      ):
        try {
          final count = save
              ? await api.saveSessionState(sessionId, path)
              : await api.loadSessionState(sessionId, path);
          toMain.send(StateResult(requestId, count, null));
        } catch (e) {
          toMain.send(StateResult(requestId, null, e.toString()));
        }
      case ShutdownCommand():
        commands.close();
        Isolate.exit();
    }
  }
}
