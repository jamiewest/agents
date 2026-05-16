import 'container_user.dart';
import 'docker_network_mode.dart';
import 'shell_mode.dart';
import 'shell_policy.dart';

/// Configuration options for [DockerShellExecutor].
class DockerShellExecutorOptions {
  /// Creates [DockerShellExecutorOptions].
  const DockerShellExecutorOptions({
    this.image =
        'mcr.microsoft.com/azurelinux/base/core:3.0',
    this.containerName,
    this.mode = ShellMode.persistent,
    this.hostWorkdir,
    this.containerWorkdir = '/workspace',
    this.mountReadonly = true,
    this.memoryBytes = 512 * 1024 * 1024,
    this.pidsLimit = 256,
    this.user = ContainerUser.defaultUser,
    this.readOnlyRoot = true,
    this.network = DockerNetworkMode.none,
    this.extraRunArgs,
    this.environment,
    this.policy,
    this.timeout = const Duration(seconds: 30),
    this.maxOutputBytes = 64 * 1024,
    this.dockerBinary = 'docker',
  });

  /// OCI container image to use. Must include bash and sleep.
  final String image;

  /// Optional fixed container name. When `null`, a unique name is generated.
  final String? containerName;

  /// Whether to run each command in a fresh container or reuse a persistent
  /// one. Defaults to [ShellMode.persistent].
  final ShellMode mode;

  /// Host directory to mount into the container at [containerWorkdir].
  /// When `null`, no volume is mounted.
  final String? hostWorkdir;

  /// Path inside the container where [hostWorkdir] is mounted.
  final String containerWorkdir;

  /// When `true`, the host directory mount is read-only.
  final bool mountReadonly;

  /// Memory limit for the container in bytes. Defaults to 512 MiB.
  final int memoryBytes;

  /// Maximum number of processes (PID limit). Defaults to 256.
  final int pidsLimit;

  /// UID/GID for the container process. Defaults to [ContainerUser.defaultUser]
  /// (nobody/nogroup, UID/GID 65534).
  final ContainerUser user;

  /// When `true`, the container root filesystem is read-only (tmpfs is still
  /// available for writes to `/tmp`).
  final bool readOnlyRoot;

  /// Docker network mode. Defaults to [DockerNetworkMode.none] (no network).
  final String network;

  /// Additional arguments passed to `docker run` before the image name.
  final List<String>? extraRunArgs;

  /// Extra environment variables injected into the container.
  final Map<String, String>? environment;

  /// Optional policy for allow/deny command filtering.
  final ShellPolicy? policy;

  /// Per-command timeout. `null` disables timeouts. Defaults to 30 seconds.
  final Duration? timeout;

  /// Maximum output captured per command in UTF-8 bytes before head+tail
  /// truncation is applied. Defaults to 64 KiB.
  final int maxOutputBytes;

  /// Docker (or compatible runtime) binary name or path. Defaults to `'docker'`.
  final String dockerBinary;
}
