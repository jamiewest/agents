import 'shell_family.dart';

/// A point-in-time snapshot of the shell environment the agent is using.
final class ShellEnvironmentSnapshot {
  /// Creates a [ShellEnvironmentSnapshot].
  const ShellEnvironmentSnapshot({
    required this.family,
    required this.osDescription,
    required this.shellVersion,
    required this.workingDirectory,
    required this.toolVersions,
  });

  /// Shell family (POSIX or PowerShell).
  final ShellFamily family;

  /// Operating system description string.
  final String osDescription;

  /// Reported shell version, or `null` if probing failed.
  final String? shellVersion;

  /// Current working directory at probe time, or empty string if probing
  /// failed.
  final String workingDirectory;

  /// Map of probed CLI tool name to reported version string, or `null` when
  /// the tool is not installed.
  final Map<String, String?> toolVersions;
}
