import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'head_tail_buffer.dart';
import 'shell_family.dart';
import 'shell_result.dart';

/// Manages a persistent shell subprocess using a sentinel protocol to bracket
/// each command's stdout and capture its exit code.
///
/// The sentinel protocol injects unique marker strings before and after the
/// user's command. Reading stdout until the end-sentinel appears signals
/// command completion; the exit code is embedded in the marker.
///
/// This class is not thread-safe. Use one instance per agent session.
class ShellSession {
  /// Creates a [ShellSession] that will launch [binary] with [persistentArgv].
  ShellSession({
    required this.binary,
    required this.persistentArgv,
    required this.family,
    this.workingDirectory,
    this.environment,
  });

  /// The shell binary to launch.
  final String binary;

  /// The argv for persistent-mode launch (e.g. `['--noprofile', '--norc']`).
  final List<String> persistentArgv;

  /// The shell family, used to select quoting and sentinel strategies.
  final ShellFamily family;

  /// Optional working directory for the shell process.
  final String? workingDirectory;

  /// Optional environment variables to inject.
  final Map<String, String>? environment;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  final List<String> _stdoutLines = [];
  String? _currentSentinelEnd;
  Completer<int>? _commandCompleter;
  bool _initialized = false;
  int _cmdCounter = 0;

  // ── Static utility methods (exposed for testing) ─────────────────────────

  /// POSIX single-quote a string so it cannot be interpreted by the shell.
  ///
  /// Embedded single quotes use the close-escape-reopen pattern:
  /// `a'b` → `'a'\''b'`.
  static String quotePosix(String s) => "'${s.replaceAll("'", "'\\''")}'";

  /// PowerShell single-quote a string so variables and subexpressions are not
  /// expanded. Embedded single quotes are doubled: `a'b` → `'a''b'`.
  static String quotePowerShell(String s) => "'${s.replaceAll("'", "''")}'";

  /// Truncate [input] to at most [cap] UTF-8 bytes, preserving a head and tail
  /// section with a `[... truncated N bytes ...]` marker in the middle.
  ///
  /// Rune boundaries are respected; unpaired surrogates are substituted with
  /// U+FFFD. Returns `(text, truncated)`.
  static (String text, bool truncated) truncateHeadTail(
    String input, {
    required int cap,
  }) {
    if (input.isEmpty) return ('', false);

    final headCap = cap ~/ 2;
    final tailCap = cap - headCap;

    final head = <int>[];
    final tail = Queue<Uint8List>();
    int tailBytes = 0;
    int totalBytes = 0;

    final units = input.codeUnits;
    var i = 0;
    while (i < units.length) {
      final u = units[i];
      int codePoint;

      if (u >= 0xD800 && u <= 0xDBFF) {
        if (i + 1 < units.length &&
            units[i + 1] >= 0xDC00 &&
            units[i + 1] <= 0xDFFF) {
          // Valid surrogate pair.
          codePoint =
              0x10000 + ((u - 0xD800) << 10) + (units[i + 1] - 0xDC00);
          i += 2;
        } else {
          // Unpaired high surrogate → U+FFFD.
          codePoint = 0xFFFD;
          i++;
        }
      } else if (u >= 0xDC00 && u <= 0xDFFF) {
        // Unpaired low surrogate → U+FFFD.
        codePoint = 0xFFFD;
        i++;
      } else {
        codePoint = u;
        i++;
      }

      final bytes = _encodeCodePoint(codePoint);
      final n = bytes.length;
      totalBytes += n;

      if (head.length + n <= headCap) {
        head.addAll(bytes);
      } else {
        final chunk = Uint8List.fromList(bytes);
        tail.add(chunk);
        tailBytes += n;
        while (tailBytes > tailCap && tail.isNotEmpty) {
          tailBytes -= tail.removeFirst().length;
        }
      }
    }

    if (totalBytes <= cap) {
      final combined = Uint8List(head.length + tailBytes);
      combined.setAll(0, head);
      var offset = head.length;
      for (final chunk in tail) {
        combined.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      return (utf8.decode(combined, allowMalformed: true), false);
    }

    final dropped = totalBytes - head.length - tailBytes;
    final headStr = utf8.decode(head, allowMalformed: true);

    final tailRaw = Uint8List(tailBytes);
    var tailOffset = 0;
    for (final chunk in tail) {
      tailRaw.setRange(tailOffset, tailOffset + chunk.length, chunk);
      tailOffset += chunk.length;
    }
    final tailStr = utf8.decode(tailRaw, allowMalformed: true);

    final sb = StringBuffer(headStr)
      ..writeln()
      ..write('[... truncated $dropped bytes ...]')
      ..writeln()
      ..write(tailStr);

    return (sb.toString(), true);
  }

  static List<int> _encodeCodePoint(int cp) {
    if (cp < 0x80) return [cp];
    if (cp < 0x800) {
      return [0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)];
    }
    if (cp < 0x10000) {
      return [
        0xE0 | (cp >> 12),
        0x80 | ((cp >> 6) & 0x3F),
        0x80 | (cp & 0x3F),
      ];
    }
    return [
      0xF0 | (cp >> 18),
      0x80 | ((cp >> 12) & 0x3F),
      0x80 | ((cp >> 6) & 0x3F),
      0x80 | (cp & 0x3F),
    ];
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Starts the persistent shell subprocess. Idempotent.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final process = await Process.start(
      binary,
      persistentArgv,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    _process = process;

    // Drain stderr to prevent pipe stalls. Persistent-mode stderr is not
    // captured per-command (only stateless mode captures stderr).
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((_) {});

    // Subscribe to stdout; dispatch each line to the active command.
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStdoutLine);
  }

  void _onStdoutLine(String line) {
    final sentinel = _currentSentinelEnd;
    if (sentinel == null) return; // Idle — discard startup noise.

    if (line.startsWith(sentinel)) {
      final ecStr = line.substring(sentinel.length);
      final exitCode = int.tryParse(ecStr.trim()) ?? -1;
      _commandCompleter?.complete(exitCode);
      _commandCompleter = null;
      _currentSentinelEnd = null;
      return;
    }

    _stdoutLines.add(line);
  }

  // ── Command execution ─────────────────────────────────────────────────────

  /// Runs [command] and returns a [ShellResult]. Must be called after
  /// [initialize].
  Future<ShellResult> runCommand(
    String command, {
    Duration? timeout,
    int maxOutputBytes = 64 * 1024,
    String? confineWorkingDirectory,
  }) async {
    final process = _process;
    if (process == null) throw StateError('ShellSession not initialized.');

    final sentinelEnd = '__AF_END_${DateTime.now().microsecondsSinceEpoch}_${_cmdCounter++}__';
    _currentSentinelEnd = sentinelEnd;
    _stdoutLines.clear();
    _commandCompleter = Completer<int>();

    final wrappedCmd = _wrapCommand(
      command,
      sentinelEnd,
      confineWorkingDirectory,
    );

    final stopwatch = Stopwatch()..start();
    process.stdin.writeln(wrappedCmd);
    await process.stdin.flush();

    bool timedOut = false;
    int exitCode;

    if (timeout != null) {
      exitCode = await _commandCompleter!.future.timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          _commandCompleter = null;
          _currentSentinelEnd = null;
          try {
            process.kill(ProcessSignal.sigint);
          } catch (_) {}
          return 124;
        },
      );
    } else {
      exitCode = await _commandCompleter!.future;
    }

    stopwatch.stop();

    final buf = HeadTailBuffer(maxOutputBytes);
    for (final line in _stdoutLines) {
      buf.appendLine(line);
    }
    final (stdout, truncated) = buf.toFinalString();

    return ShellResult(
      stdout: stdout,
      stderr: '',
      exitCode: exitCode,
      duration: stopwatch.elapsed,
      truncated: truncated,
      timedOut: timedOut,
    );
  }

  String _wrapCommand(
    String command,
    String sentinelEnd,
    String? confineWorkdir,
  ) {
    final sb = StringBuffer();

    if (confineWorkdir != null) {
      sb.writeln(_cdCommand(confineWorkdir));
    }

    sb.writeln(command);

    if (family == ShellFamily.powerShell) {
      // Capture last exit code, then print sentinel+code on one line.
      // Use raw string literal for the PowerShell variable references.
      sb.writeln(
        r'$__af_ec__ = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }',
      );
      // Combine sentinel prefix (Dart interpolation) with PS variable (raw).
      sb.write('Write-Host "$sentinelEnd' r'$__af_ec__"');
    } else {
      // POSIX: capture exit code, then echo sentinel+code.
      // Split across adjacent string literals to avoid Dart interpolating $?.
      sb.writeln(r'__af_ec__=$?');
      // quotePosix handles the sentinel; r'...' prevents Dart interpolation.
      sb.write('printf ' r"'%s%s\n'" ' ${quotePosix(sentinelEnd)} ' r'"$__af_ec__"');
    }

    return sb.toString();
  }

  String _cdCommand(String dir) => family == ShellFamily.powerShell
      ? 'Set-Location ${quotePowerShell(dir)}'
      : 'cd ${quotePosix(dir)}';

  // ── Dispose ───────────────────────────────────────────────────────────────

  /// Kills the shell process and releases resources.
  Future<void> dispose() async {
    await _stdoutSub?.cancel();
    _stdoutSub = null;
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        process.kill();
      } catch (_) {}
      await process.exitCode;
    }
  }
}
