import 'shell_environment_snapshot.dart';
import 'shell_family.dart';

/// Configuration options for [ShellEnvironmentProvider].
class ShellEnvironmentProviderOptions {
  /// Creates [ShellEnvironmentProviderOptions].
  const ShellEnvironmentProviderOptions({
    this.probeTools = const ['git', 'dotnet', 'node', 'python', 'docker'],
    this.overrideFamily,
    this.probeTimeout = const Duration(seconds: 5),
    this.instructionsFormatter,
  });

  /// CLI tool names to probe for version information. Defaults to a standard
  /// developer toolset.
  final List<String> probeTools;

  /// When set, overrides automatic shell family detection.
  final ShellFamily? overrideFamily;

  /// Timeout for each tool-version probe. Defaults to 5 seconds.
  final Duration probeTimeout;

  /// Custom formatter that turns a [ShellEnvironmentSnapshot] into an
  /// instructions string injected into [AIContext]. When `null`, a built-in
  /// default formatter is used.
  final String Function(ShellEnvironmentSnapshot)? instructionsFormatter;
}
