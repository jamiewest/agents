import 'package:extensions/system.dart';

import 'shell_result.dart';

/// Pluggable backend that runs shell commands on behalf of a tool.
///
/// [LocalShellExecutor] runs commands directly on the host (no isolation;
/// approval-in-the-loop is the security boundary). [DockerShellExecutor] runs
/// them inside a container with resource limits, network isolation, and a
/// non-root user.
///
/// **Lifetime.** [initializeAsync] is invoked at most once per instance
/// (idempotent); [dispose] tears the executor down at the end of its life.
///
/// **Concurrency and session ownership.** A single executor instance is
/// intended to serve a single conversation/agent session. Stateless mode is
/// safe to share across concurrent callers (each [runAsync] spawns a fresh
/// process). Persistent mode is *not* shareable: a single long-lived shell
/// process backs every call and carries mutable state. Build one executor per
/// session and dispose it when the session ends.
abstract class ShellExecutor {
  /// Eagerly initialize the backend. Idempotent; subsequent calls are no-ops
  /// once the executor is started.
  Future<void> initializeAsync({CancellationToken? cancellationToken}) =>
      Future.value();

  /// Run a single command and return its result. Implementations apply the
  /// configured per-command timeout and surface it via
  /// [ShellResult.timedOut] + `exitCode = 124`.
  Future<ShellResult> runAsync(
    String command, {
    CancellationToken? cancellationToken,
  });

  /// Tears down the executor and releases any underlying resources.
  Future<void> dispose();
}
