import 'shell_mode.dart';
import 'shell_policy.dart';

/// Configuration options for [LocalShellExecutor].
class LocalShellExecutorOptions {
  /// Creates [LocalShellExecutorOptions].
  const LocalShellExecutorOptions({
    this.mode = ShellMode.persistent,
    this.shell,
    this.shellArgv,
    this.workingDirectory,
    this.confineWorkingDirectory = false,
    this.environment,
    this.cleanEnvironment = false,
    this.policy,
    this.timeout = const Duration(seconds: 30),
    this.maxOutputBytes = 64 * 1024,
    this.acknowledgeUnsafe = false,
  });

  /// Whether to run each command in a fresh process or reuse a persistent
  /// shell. Defaults to [ShellMode.persistent].
  final ShellMode mode;

  /// Override the shell binary. Mutually exclusive with [shellArgv].
  final String? shell;

  /// Override the full shell launch argv. Mutually exclusive with [shell].
  final List<String>? shellArgv;

  /// Working directory for the spawned shell. Defaults to the current
  /// process working directory.
  final String? workingDirectory;

  /// When `true` (persistent mode only), the working directory is reset to
  /// [workingDirectory] before each command, preventing `cd` from leaking
  /// across calls.
  final bool confineWorkingDirectory;

  /// Extra environment variables injected into the shell process.
  final Map<String, String>? environment;

  /// When `true`, the child shell does not inherit the parent process
  /// environment (except for the variables in
  /// [EnvironmentSanitizer.preservedVariables]).
  final bool cleanEnvironment;

  /// Optional policy for allow/deny command filtering.
  final ShellPolicy? policy;

  /// Per-command timeout. `null` disables timeouts. Defaults to 30 seconds.
  final Duration? timeout;

  /// Maximum output captured per command in UTF-8 bytes before head+tail
  /// truncation is applied. Defaults to 64 KiB.
  final int maxOutputBytes;

  /// Opt-in flag required to call `asAIFunction(requireApproval: false)` on a
  /// [LocalShellExecutor]. This acknowledges that running model-generated
  /// commands without approval is unsafe. For [DockerShellExecutor], no
  /// acknowledgement is required.
  final bool acknowledgeUnsafe;
}
