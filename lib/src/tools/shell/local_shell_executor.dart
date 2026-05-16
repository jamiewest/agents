import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'environment_sanitizer.dart';
import 'head_tail_buffer.dart';
import 'local_shell_executor_options.dart';
import 'shell_executor.dart';
import 'shell_family.dart';
import 'shell_mode.dart';
import 'shell_policy.dart';
import 'shell_resolver.dart';
import 'shell_result.dart';
import 'shell_session.dart';

/// A [ShellExecutor] that runs commands directly on the host machine.
///
/// **Security model.** The primary security control is approval-in-the-loop:
/// [asAIFunction] wraps the executor in an [ApprovalRequiredAIFunction] by
/// default. A [ShellPolicy] may be configured as a UX guardrail to catch
/// common accidental destructive commands, but it is not a security boundary.
///
/// Persistent mode reuses a single long-lived shell process, so `cd` and
/// exported variables persist across calls. Use one executor per session and
/// dispose it when the session ends.
class LocalShellExecutor extends ShellExecutor {
  /// Creates a [LocalShellExecutor] with the given [options].
  ///
  /// Throws [ArgumentError] if both [LocalShellExecutorOptions.shell] and
  /// [LocalShellExecutorOptions.shellArgv] are set.
  LocalShellExecutor([LocalShellExecutorOptions? options])
      : _options = options ?? const LocalShellExecutorOptions() {
    if (_options.shell != null && _options.shellArgv != null) {
      throw ArgumentError(
        'Cannot specify both shell and shellArgv in LocalShellExecutorOptions.',
      );
    }
  }

  /// The default per-command timeout.
  static const Duration defaultTimeout = Duration(seconds: 30);

  final LocalShellExecutorOptions _options;
  ResolvedShell? _resolvedShell;
  ShellSession? _session;

  // ── Shell resolution ──────────────────────────────────────────────────────

  ResolvedShell _getResolvedShell() {
    if (_resolvedShell != null) return _resolvedShell!;

    final List<String> candidates;
    if (_options.shellArgv != null) {
      candidates = [_options.shellArgv!.first];
    } else if (_options.shell != null) {
      candidates = [_options.shell!];
    } else {
      candidates = ShellResolver.defaultCandidates();
    }

    final resolved = ShellResolver.resolveArgv(candidates);

    if (_options.mode == ShellMode.persistent &&
        resolved.family == ShellFamily.posix &&
        resolved.binary.toLowerCase().contains('cmd')) {
      throw UnsupportedError(
        'Persistent mode is not supported for cmd.exe. '
        'Use pwsh, powershell, bash, or sh instead.',
      );
    }

    return _resolvedShell = resolved;
  }

  Map<String, String> _buildEnvironment() {
    final env = <String, String>{};
    if (!_options.cleanEnvironment) {
      env.addAll(Platform.environment);
    } else {
      // Seed with preserved variables from the parent environment.
      final parent = Platform.environment;
      for (final name in EnvironmentSanitizer.preservedVariables) {
        final value = parent[name];
        if (value != null) env[name] = value;
      }
    }
    if (_options.environment != null) {
      env.addAll(_options.environment!);
    }
    return env;
  }

  // ── ShellExecutor ─────────────────────────────────────────────────────────

  @override
  Future<void> initializeAsync({CancellationToken? cancellationToken}) async {
    if (_options.mode == ShellMode.persistent) {
      final resolved = _getResolvedShell();
      final argv = resolved.persistentArgv();
      _session = ShellSession(
        binary: resolved.binary,
        persistentArgv: argv,
        family: resolved.family,
        workingDirectory: _options.workingDirectory,
        environment: _buildEnvironment(),
      );
      await _session!.initialize();
    }
  }

  @override
  Future<ShellResult> runAsync(
    String command, {
    CancellationToken? cancellationToken,
  }) async {
    // Policy check.
    final policy = _options.policy;
    if (policy != null) {
      final outcome = policy.evaluate(ShellRequest(command));
      if (!outcome.allowed) {
        throw ShellCommandRejectedException(command, reason: outcome.reason);
      }
    }

    if (_options.mode == ShellMode.stateless) {
      return _runStateless(command);
    }
    return _runPersistent(command);
  }

  Future<ShellResult> _runStateless(String command) async {
    final resolved = _getResolvedShell();
    final argv = resolved.statelessArgvForCommand(command);
    final env = _buildEnvironment();

    final stopwatch = Stopwatch()..start();
    final process = await Process.start(
      resolved.binary,
      argv,
      environment: env,
      workingDirectory: _options.workingDirectory,
      runInShell: false,
    );

    final stdoutBuf = HeadTailBuffer(_options.maxOutputBytes);
    final stderrBuf = HeadTailBuffer(_options.maxOutputBytes);

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(stdoutBuf.appendLine);
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(stderrBuf.appendLine);

    bool timedOut = false;
    int exitCode;

    if (_options.timeout != null) {
      Timer? timer;
      final exitFuture = process.exitCode;
      final completer = Completer<int>();

      timer = Timer(_options.timeout!, () {
        if (!completer.isCompleted) {
          timedOut = true;
          try {
            process.kill(ProcessSignal.sigint);
          } catch (_) {}
          // Give the process a moment to respond to SIGINT, then force kill.
          Future.delayed(const Duration(milliseconds: 100), () {
            try {
              process.kill();
            } catch (_) {}
          });
        }
      });

      exitFuture.then((code) {
        timer?.cancel();
        if (!completer.isCompleted) completer.complete(code);
      });

      exitCode = await completer.future;
    } else {
      exitCode = await process.exitCode;
    }

    await Future.wait([stdoutDone, stderrDone]);
    stopwatch.stop();

    if (timedOut) exitCode = 124;

    final (stdout, stdoutTruncated) = stdoutBuf.toFinalString();
    final (stderr, stderrTruncated) = stderrBuf.toFinalString();

    return ShellResult(
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode,
      duration: stopwatch.elapsed,
      truncated: stdoutTruncated || stderrTruncated,
      timedOut: timedOut,
    );
  }

  Future<ShellResult> _runPersistent(String command) async {
    var session = _session;
    if (session == null) {
      final resolved = _getResolvedShell();
      session = _session = ShellSession(
        binary: resolved.binary,
        persistentArgv: resolved.persistentArgv(),
        family: resolved.family,
        workingDirectory: _options.workingDirectory,
        environment: _buildEnvironment(),
      );
      await session.initialize();
    }

    return session.runCommand(
      command,
      timeout: _options.timeout,
      maxOutputBytes: _options.maxOutputBytes,
      confineWorkingDirectory:
          _options.confineWorkingDirectory ? _options.workingDirectory : null,
    );
  }

  @override
  Future<void> dispose() async {
    await _session?.dispose();
    _session = null;
  }

  // ── AI function ───────────────────────────────────────────────────────────

  /// Returns an [AIFunction] that invokes this executor when called by a model.
  ///
  /// By default, [requireApproval] is `true`, which wraps the function in an
  /// [ApprovalRequiredAIFunction] so human approval is required before each
  /// shell command executes.
  ///
  /// To opt out of approval gating, set [requireApproval] to `false` and set
  /// [LocalShellExecutorOptions.acknowledgeUnsafe] to `true`. Running
  /// model-generated shell commands without approval is dangerous; the
  /// acknowledgement flag makes this an explicit, deliberate choice.
  AIFunction asAIFunction({bool requireApproval = true}) {
    if (!requireApproval && !_options.acknowledgeUnsafe) {
      throw StateError(
        'To disable approval gating on LocalShellExecutor, set '
        'LocalShellExecutorOptions.acknowledgeUnsafe to true. '
        'Running model-generated commands without approval is unsafe.',
      );
    }

    final inner = AIFunctionFactory.create(
      name: 'run_shell',
      description:
          'Runs a shell command and returns its stdout, stderr, and exit code.',
      parametersSchema: const {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'The shell command to execute.',
          },
        },
        'required': ['command'],
      },
      callback: (arguments, {cancellationToken}) async {
        final command = (arguments['command'] ?? '').toString();
        final result = await runAsync(command, cancellationToken: cancellationToken);
        return result.formatForModel();
      },
    );

    return requireApproval ? ApprovalRequiredAIFunction(inner) : inner;
  }
}
