import 'dart:async';

import 'package:agents/agents.dart'
    show ShellExecutor, ShellOutputChunk, ShellResult;
import 'package:extensions/system.dart';

import 'terminal_activity.dart';

/// A [ShellExecutor] decorator that mirrors every command into a
/// [TerminalActivity] session.
///
/// Wraps whichever executor the harness was configured with (local shell
/// today; ssh or container backends the same way tomorrow), so the chat
/// terminal shows commands the moment they start executing and each output
/// line as the process emits it, via the inner executor's
/// [ShellExecutor.outputEvents]. Executors that don't implement the stream
/// (its default is empty) fall back to echoing the buffered result when the
/// command completes.
class TerminalMirroringShellExecutor extends ShellExecutor {
  /// Wraps [inner], mirroring commands to [registry] under [conversationId].
  TerminalMirroringShellExecutor(
    this._inner, {
    required this.registry,
    required this.conversationId,
  });

  final ShellExecutor _inner;

  /// The registry holding the conversation's terminal session.
  final TerminalActivity registry;

  /// The conversation whose terminal this executor writes into.
  final String conversationId;

  @override
  Stream<ShellOutputChunk> get outputEvents => _inner.outputEvents;

  @override
  Future<void> initializeAsync({CancellationToken? cancellationToken}) =>
      _inner.initializeAsync(cancellationToken: cancellationToken);

  @override
  Future<ShellResult> runAsync(
    String command, {
    CancellationToken? cancellationToken,
  }) async {
    // Resolved per call, not at construction: the chat UI may open (or
    // close) its session at any point in the executor's life.
    final session = registry.sessionFor(conversationId);
    session?.beginCommand(command);
    // Built-in executors emit synchronously per line, so every chunk of this
    // command is delivered before runAsync returns. Filtering by command
    // keeps concurrent tool calls from cross-writing each other's output
    // (identical concurrent commands would interleave, which a shared
    // terminal shows anyway).
    var streamed = false;
    StreamSubscription<ShellOutputChunk>? subscription;
    if (session != null) {
      subscription = _inner.outputEvents
          .where((chunk) => chunk.command == command)
          .listen((chunk) {
            streamed = true;
            session.writeChunk(chunk);
          });
    }
    try {
      final result = await _inner.runAsync(
        command,
        cancellationToken: cancellationToken,
      );
      session?.completeCommand(result, outputStreamed: streamed);
      return result;
    } catch (error) {
      session?.failCommand(error);
      rethrow;
    } finally {
      unawaited(subscription?.cancel());
    }
  }

  @override
  Future<void> dispose() => _inner.dispose();
}
