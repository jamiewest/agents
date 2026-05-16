import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'container_user.dart';
import 'docker_shell_executor_options.dart';
import 'head_tail_buffer.dart';
import 'shell_executor.dart';
import 'shell_family.dart';
import 'shell_mode.dart';
import 'shell_policy.dart';
import 'shell_resolver.dart';
import 'shell_result.dart';
import 'shell_session.dart';

/// A [ShellExecutor] that runs commands inside a Docker container.
///
/// **Security model.** The container provides the primary isolation boundary:
/// no network, non-root user, read-only root filesystem, dropped capabilities,
/// and a memory/PID limit. [asAIFunction] still wraps in
/// [ApprovalRequiredAIFunction] by default — container isolation is not a
/// replacement for approval gating because a compromised image or privileged
/// container can still cause harm.
///
/// Persistent mode reuses a single long-lived container per instance. Use one
/// executor per session and dispose it when the session ends.
class DockerShellExecutor extends ShellExecutor {
  /// Creates a [DockerShellExecutor] with the given [options].
  DockerShellExecutor([DockerShellExecutorOptions? options])
      : _options = options ?? const DockerShellExecutorOptions(),
        containerName = (options?.containerName) ??
            'af-shell-${_randomSuffix()}';

  final DockerShellExecutorOptions _options;
  ShellSession? _session;
  bool _containerStarted = false;

  /// The name of the Docker container managed by this executor.
  final String containerName;

  static final Random _random = Random.secure();

  static String _randomSuffix() {
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ── Static argv builders (testable without Docker) ────────────────────────

  /// Builds the `docker run` argv for creating and starting the container.
  ///
  /// This is a static method so it can be tested without a Docker daemon.
  static List<String> buildRunArgv({
    required String binary,
    required String image,
    required String containerName,
    required ContainerUser user,
    required String network,
    required int memoryBytes,
    required int pidsLimit,
    required String workdir,
    required String? hostWorkdir,
    required bool mountReadonly,
    required bool readOnlyRoot,
    required Map<String, String>? extraEnv,
    required List<String>? extraArgs,
  }) {
    final argv = <String>[
      binary,
      'run',
      '-d',
      '--rm',
      '--name', containerName,
      '--user', user.toString(),
      '--network', network,
      '--memory', memoryBytes.toString(),
      '--pids-limit', pidsLimit.toString(),
      '--cap-drop', 'ALL',
      '--security-opt', 'no-new-privileges',
      '--workdir', workdir,
      '--tmpfs', '/tmp:rw,noexec,nosuid,size=64m',
    ];

    if (readOnlyRoot) argv.add('--read-only');

    if (hostWorkdir != null) {
      final mode = mountReadonly ? 'ro' : 'rw';
      argv.addAll(['-v', '$hostWorkdir:$workdir:$mode']);
    }

    if (extraEnv != null) {
      for (final entry in extraEnv.entries) {
        argv.addAll(['-e', '${entry.key}=${entry.value}']);
      }
    }

    if (extraArgs != null) argv.addAll(extraArgs);

    argv.addAll([image, 'sleep', 'infinity']);
    return argv;
  }

  /// Builds the `docker exec` argv for attaching to the persistent container.
  ///
  /// This is a static method so it can be tested without a Docker daemon.
  static List<String> buildExecArgv(String binary, String containerName) {
    return [binary, 'exec', '-i', containerName, 'bash', '--noprofile', '--norc'];
  }

  /// Returns `true` when [binary] is available on PATH.
  static Future<bool> isAvailableAsync({String binary = 'docker'}) async {
    try {
      final result = await Process.run(binary, ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // ── ShellExecutor ─────────────────────────────────────────────────────────

  @override
  Future<void> initializeAsync({CancellationToken? cancellationToken}) async {
    if (_options.mode == ShellMode.persistent) {
      await _ensureContainerRunning();
      _session = ShellSession(
        binary: _options.dockerBinary,
        persistentArgv: buildExecArgv(
          _options.dockerBinary,
          containerName,
        ).sublist(1), // Remove binary — Process.start takes it separately.
        family: ShellFamily.posix,
        workingDirectory: null,
        environment: null,
      );
      await _session!.initialize();
    }
  }

  @override
  Future<ShellResult> runAsync(
    String command, {
    CancellationToken? cancellationToken,
  }) async {
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

  Future<void> _ensureContainerRunning() async {
    if (_containerStarted) return;
    _containerStarted = true;

    final argv = buildRunArgv(
      binary: _options.dockerBinary,
      image: _options.image,
      containerName: containerName,
      user: _options.user,
      network: _options.network,
      memoryBytes: _options.memoryBytes,
      pidsLimit: _options.pidsLimit,
      workdir: _options.containerWorkdir,
      hostWorkdir: _options.hostWorkdir,
      mountReadonly: _options.mountReadonly,
      readOnlyRoot: _options.readOnlyRoot,
      extraEnv: _options.environment,
      extraArgs: _options.extraRunArgs,
    );

    final result = await Process.run(
      argv.first,
      argv.sublist(1),
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        argv.first,
        argv.sublist(1),
        'Failed to start Docker container: ${result.stderr}',
        result.exitCode,
      );
    }
  }

  Future<ShellResult> _runStateless(String command) async {
    final resolved = ShellResolver.resolveArgv(['/bin/bash']);
    final argv = resolved.statelessArgvForCommand(command);

    final execArgv = [
      _options.dockerBinary,
      'run',
      '--rm',
      '--network', _options.network,
      '--user', _options.user.toString(),
      '--memory', _options.memoryBytes.toString(),
      '--pids-limit', _options.pidsLimit.toString(),
      '--cap-drop', 'ALL',
      '--security-opt', 'no-new-privileges',
      '--workdir', _options.containerWorkdir,
      if (_options.readOnlyRoot) '--read-only',
      '--tmpfs', '/tmp:rw,noexec,nosuid,size=64m',
      _options.image,
      '/bin/bash',
      ...argv,
    ];

    final stopwatch = Stopwatch()..start();
    final process = await Process.start(
      execArgv.first,
      execArgv.sublist(1),
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
      final completer = Completer<int>();
      timer = Timer(_options.timeout!, () {
        if (!completer.isCompleted) {
          timedOut = true;
          try {
            process.kill();
          } catch (_) {}
        }
      });
      process.exitCode.then((code) {
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
    if (_session == null) {
      await _ensureContainerRunning();
      final execArgv = buildExecArgv(_options.dockerBinary, containerName);
      _session = ShellSession(
        binary: execArgv.first,
        persistentArgv: execArgv.sublist(1),
        family: ShellFamily.posix,
        workingDirectory: null,
        environment: null,
      );
      await _session!.initialize();
    }

    return _session!.runCommand(
      command,
      timeout: _options.timeout,
      maxOutputBytes: _options.maxOutputBytes,
    );
  }

  @override
  Future<void> dispose() async {
    await _session?.dispose();
    _session = null;

    if (_containerStarted) {
      _containerStarted = false;
      try {
        await Process.run(_options.dockerBinary, ['rm', '-f', containerName]);
      } catch (_) {}
    }
  }

  // ── AI function ───────────────────────────────────────────────────────────

  /// Returns an [AIFunction] that invokes this executor when called by a model.
  ///
  /// [requireApproval] defaults to `true`, wrapping in
  /// [ApprovalRequiredAIFunction]. Pass `false` to opt out of approval gating
  /// (the container provides isolation, but approval is still recommended).
  AIFunction asAIFunction({bool requireApproval = true}) {
    final inner = AIFunctionFactory.create(
      name: 'run_shell',
      description:
          'Runs a shell command inside a Docker container and returns its '
          'stdout, stderr, and exit code.',
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
