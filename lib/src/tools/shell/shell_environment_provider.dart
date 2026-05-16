import 'dart:io';

import 'package:extensions/system.dart';

import '../../abstractions/ai_context.dart';
import '../../abstractions/ai_context_provider.dart';
import 'shell_environment_provider_options.dart';
import 'shell_environment_snapshot.dart';
import 'shell_executor.dart';
import 'shell_family.dart';

/// An [AIContextProvider] that probes the shell environment and injects
/// instructions describing the OS, shell version, and available tools.
///
/// The snapshot is captured once per executor lifetime and cached. To refresh
/// it, create a new [ShellEnvironmentProvider].
class ShellEnvironmentProvider extends AIContextProvider {
  /// Creates a [ShellEnvironmentProvider] backed by [executor].
  ShellEnvironmentProvider(
    this._executor, {
    ShellEnvironmentProviderOptions? options,
  }) : _options = options ?? const ShellEnvironmentProviderOptions();

  final ShellExecutor _executor;
  final ShellEnvironmentProviderOptions _options;
  ShellEnvironmentSnapshot? _snapshot;

  // ── AIContextProvider ─────────────────────────────────────────────────────

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final snapshot = await probe(cancellationToken: cancellationToken);
    final formatter = _options.instructionsFormatter ?? defaultFormatter;
    return AIContext()..instructions = formatter(snapshot);
  }

  /// Probes the shell environment and returns a [ShellEnvironmentSnapshot].
  ///
  /// The result is cached; subsequent calls return the cached value.
  Future<ShellEnvironmentSnapshot> probe({
    CancellationToken? cancellationToken,
  }) async {
    return _snapshot ??= await _probe(cancellationToken);
  }

  /// The default formatter used when no custom
  /// [ShellEnvironmentProviderOptions.instructionsFormatter] is configured.
  static String defaultFormatter(ShellEnvironmentSnapshot snapshot) =>
      _defaultFormatter(snapshot);

  // ── Probing ───────────────────────────────────────────────────────────────

  Future<ShellEnvironmentSnapshot> _probe(
    CancellationToken? cancellationToken,
  ) async {
    final family = _options.overrideFamily ?? _detectFamily();

    String? shellVersion;
    String workingDirectory = '';

    try {
      final versionCmd = family == ShellFamily.powerShell
          ? r'$PSVersionTable.PSVersion.ToString()'
          : 'echo "\$BASH_VERSION"';
      final vResult = await _executor
          .runAsync(versionCmd, cancellationToken: cancellationToken)
          .timeout(_options.probeTimeout);
      shellVersion = vResult.stdout.trim().isNotEmpty
          ? vResult.stdout.trim()
          : vResult.stderr.trim().isNotEmpty
              ? vResult.stderr.trim()
              : null;
    } catch (_) {}

    try {
      final pwdCmd =
          family == ShellFamily.powerShell ? '(Get-Location).Path' : 'pwd';
      final pwdResult = await _executor
          .runAsync(pwdCmd, cancellationToken: cancellationToken)
          .timeout(_options.probeTimeout);
      workingDirectory = pwdResult.stdout.trim();
    } catch (_) {}

    final toolVersions = <String, String?>{};
    final seen = <String>{};
    for (final tool in _options.probeTools) {
      final normalized = tool.toLowerCase();
      if (!seen.add(normalized)) continue; // deduplicate case-insensitively
      if (!_isValidToolName(tool)) continue;

      try {
        final cmd = family == ShellFamily.powerShell
            ? '(& $tool --version 2>&1 | Select-Object -First 1)'
            : '$tool --version 2>&1 | head -1';
        final result = await _executor
            .runAsync(cmd, cancellationToken: cancellationToken)
            .timeout(_options.probeTimeout);
        final out =
            result.stdout.trim().isNotEmpty ? result.stdout.trim() : result.stderr.trim();
        toolVersions[tool] = out.isNotEmpty ? out : null;
      } catch (_) {
        toolVersions[tool] = null;
      }
    }

    return ShellEnvironmentSnapshot(
      family: family,
      osDescription: Platform.operatingSystemVersion,
      shellVersion: shellVersion,
      workingDirectory: workingDirectory,
      toolVersions: toolVersions,
    );
  }

  static ShellFamily _detectFamily() {
    if (Platform.isWindows) return ShellFamily.powerShell;
    return ShellFamily.posix;
  }

  static bool _isValidToolName(String name) {
    // Reject names containing shell metacharacters.
    return !name.contains(RegExp(r'[;&|`$<>\\(){}!#\s]'));
  }

  static String _defaultFormatter(ShellEnvironmentSnapshot snapshot) {
    final sb = StringBuffer();
    sb.writeln('You are operating in a shell environment.');
    sb.writeln('OS: ${snapshot.osDescription}');
    sb.writeln(
      'Shell: ${snapshot.family == ShellFamily.powerShell ? 'PowerShell' : 'POSIX'}'
      '${snapshot.shellVersion != null ? ' (${snapshot.shellVersion})' : ''}',
    );
    if (snapshot.workingDirectory.isNotEmpty) {
      sb.writeln('Working directory: ${snapshot.workingDirectory}');
    }

    if (snapshot.family == ShellFamily.powerShell) {
      sb.writeln(
        'Use PowerShell syntax. '
        'Set variables with \$env:NAME = "value". '
        'Change directory with Set-Location.',
      );
    } else {
      sb.writeln(
        'Use POSIX shell syntax (bash/sh). '
        'Set variables with export NAME=value. '
        'Change directory with cd.',
      );
    }

    final installed = snapshot.toolVersions.entries
        .where((e) => e.value != null)
        .toList();
    if (installed.isNotEmpty) {
      sb.writeln('Available tools:');
      for (final entry in installed) {
        sb.writeln('  ${entry.key}: ${entry.value}');
      }
    }

    return sb.toString().trimRight();
  }
}
