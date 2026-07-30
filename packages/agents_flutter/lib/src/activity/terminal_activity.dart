import 'dart:async';
import 'dart:collection';

import 'package:agents/agents.dart'
    show ShellOutputChannel, ShellOutputChunk, ShellResult;
import 'package:flutter/foundation.dart';

/// Registry of per-conversation chat terminal sessions.
///
/// Each session carries a replayable ring of [TerminalEvent]s mirroring the
/// shell commands a conversation's agent executes — the command line as it
/// starts, then its output and exit status as it completes.
/// `TerminalMirroringShellExecutor` feeds a session from inside the tool
/// pipeline; the host UI renders it however it likes (the reference app
/// replays events into an xterm buffer docked under the transcript). Keying
/// by conversation keeps concurrent runs (a background task next to the
/// foreground chat) from bleeding output into each other's terminals.
class TerminalActivity {
  final Map<String, ChatTerminalSession> _sessions = {};
  final Map<String, int> _refCounts = {};

  /// Normalizes delegate/child scopes (`parent#delegate`) onto the parent
  /// conversation's session, so a delegate's shell commands surface in the
  /// foreground chat's terminal.
  static String _rootOf(String conversationId) =>
      conversationId.split('#').first;

  /// Acquires the session for [conversationId]; pair with [release].
  ChatTerminalSession listen(String conversationId) {
    final key = _rootOf(conversationId);
    _refCounts[key] = (_refCounts[key] ?? 0) + 1;
    return _sessions.putIfAbsent(key, ChatTerminalSession.new);
  }

  /// Releases one [listen] ref; the session is disposed at zero.
  void release(String conversationId) {
    final key = _rootOf(conversationId);
    final count = (_refCounts[key] ?? 1) - 1;
    if (count > 0) {
      _refCounts[key] = count;
      return;
    }
    _refCounts.remove(key);
    _sessions.remove(key)?.dispose();
  }

  /// The session for [conversationId]'s conversation, or null when no chat
  /// holds it — so background runs cost nothing and buffer nothing.
  ChatTerminalSession? sessionFor(String conversationId) =>
      _sessions[_rootOf(conversationId)];
}

/// One semantic entry in a conversation's terminal history.
///
/// Events carry raw shell data, not presentation: line-ending conversion,
/// colors, and status formatting are the renderer's concern, which is what
/// keeps this subsystem free of terminal-widget dependencies.
sealed class TerminalEvent {
  const TerminalEvent();
}

/// A command was echoed behind the prompt as it started executing.
final class TerminalCommandStarted extends TerminalEvent {
  /// Creates a started event for [command].
  const TerminalCommandStarted(this.command);

  /// The command line as handed to the executor.
  final String command;
}

/// One live output chunk from the running command.
final class TerminalOutput extends TerminalEvent {
  /// Creates an output event.
  const TerminalOutput(this.text, {required this.isError});

  /// The chunk's text, line endings as the process emitted them.
  final String text;

  /// Whether the chunk came from stderr.
  final bool isError;
}

/// The running command finished.
final class TerminalCommandCompleted extends TerminalEvent {
  /// Creates a completed event carrying the executor's [result].
  const TerminalCommandCompleted(this.result, {required this.outputStreamed});

  /// The buffered result, including exit code, duration, and output.
  final ShellResult result;

  /// Whether the command's output already arrived live as [TerminalOutput]
  /// events; when false the renderer shows [ShellResult.stdout]/`stderr`
  /// from the result instead.
  final bool outputStreamed;
}

/// The running command failed before producing a result (policy rejection,
/// executor error).
final class TerminalCommandFailed extends TerminalEvent {
  /// Creates a failure event.
  const TerminalCommandFailed(this.error);

  /// The failure, rendered as text.
  final String error;
}

/// The session's history was cleared.
///
/// Emitted on the event stream but never stored: after a clear the ring is
/// empty, so late-attaching renderers replay nothing.
final class TerminalCleared extends TerminalEvent {
  /// Creates a cleared event.
  const TerminalCleared();
}

/// One conversation's live terminal history: a capped ring of every shell
/// command the agent has run, plus the panel-facing state around it.
///
/// Notifies when panel-relevant state changes — a command starting or
/// finishing, or the history being cleared. Output chunks flow through
/// [onEvent] without notification, since panel-level state is unchanged;
/// renderers follow the stream (and replay [events] when they attach).
class ChatTerminalSession extends ChangeNotifier {
  /// Ring capacity; the oldest events fall off past this.
  static const int maxEvents = 4000;

  final ListQueue<TerminalEvent> _events = ListQueue();
  // Sync delivery preserves the pre-split timing semantics: a live output
  // line reached the terminal buffer the instant the process emitted it,
  // not a microtask later. Renderer callbacks must not re-enter the
  // session.
  final StreamController<TerminalEvent> _eventController =
      StreamController.broadcast(sync: true);

  int _commandCount = 0;
  String? _runningCommand;

  /// The history so far, oldest first, for replay on renderer attach.
  List<TerminalEvent> get events => List.unmodifiable(_events);

  /// Live events as they happen; a broadcast stream.
  Stream<TerminalEvent> get onEvent => _eventController.stream;

  /// Whether any command has been echoed since the last [clear]; the panel
  /// stays hidden until this turns true.
  bool get hasOutput => _commandCount > 0;

  /// The command currently executing, or null between commands.
  String? get runningCommand => _runningCommand;

  /// Commands echoed since the last [clear].
  int get commandCount => _commandCount;

  /// Records [command] as it starts executing.
  void beginCommand(String command) {
    _add(TerminalCommandStarted(command));
    _commandCount++;
    _runningCommand = command;
    notifyListeners();
  }

  /// Records one live output chunk from the running command.
  void writeChunk(ShellOutputChunk chunk) => _add(
    TerminalOutput(
      chunk.text,
      isError: chunk.channel == ShellOutputChannel.stderr,
    ),
  );

  /// Records a finished command's result — including, when the executor
  /// could not stream live ([outputStreamed] false), the buffered output a
  /// renderer should show in place of streamed chunks.
  void completeCommand(ShellResult result, {bool outputStreamed = false}) {
    _add(TerminalCommandCompleted(result, outputStreamed: outputStreamed));
    _runningCommand = null;
    notifyListeners();
  }

  /// Records a command failure (rejection, executor error).
  void failCommand(Object error) {
    _add(TerminalCommandFailed('$error'));
    _runningCommand = null;
    notifyListeners();
  }

  /// Drops the history and hides the panel until the next command.
  void clear() {
    _events.clear();
    _commandCount = 0;
    _runningCommand = null;
    if (!_eventController.isClosed) {
      _eventController.add(const TerminalCleared());
    }
    notifyListeners();
  }

  void _add(TerminalEvent event) {
    _events.add(event);
    while (_events.length > maxEvents) {
      _events.removeFirst();
    }
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  @override
  void dispose() {
    _eventController.close();
    super.dispose();
  }
}
