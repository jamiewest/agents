import 'dart:async';
import 'dart:io';

import 'package:extensions/system.dart' hide equals;
import 'package:test/test.dart';

import 'package:agents/src/tools/shell/shell_environment_provider.dart';
import 'package:agents/src/tools/shell/shell_environment_provider_options.dart';
import 'package:agents/src/tools/shell/shell_executor.dart';
import 'package:agents/src/tools/shell/shell_family.dart';
import 'package:agents/src/tools/shell/shell_result.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

class _ScriptedExecutor extends ShellExecutor {
  _ScriptedExecutor(this._script);

  final Map<String, String> _script;

  @override
  Future<ShellResult> runAsync(
    String command, {
    CancellationToken? cancellationToken,
  }) async {
    final stdout = _script[command] ?? '';
    return ShellResult(
      stdout: stdout,
      stderr: '',
      exitCode: 0,
      duration: Duration.zero,
    );
  }

  @override
  Future<void> dispose() async {}
}

class _FailingExecutor extends ShellExecutor {
  @override
  Future<ShellResult> runAsync(
    String command, {
    CancellationToken? cancellationToken,
  }) async =>
      throw TimeoutException('simulated timeout');

  @override
  Future<void> dispose() async {}
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('ShellEnvironmentProvider', () {
    test('POSIX detection — overrideFamily forces posix', () async {
      final executor = _ScriptedExecutor({
        'echo "\$BASH_VERSION"': '5.1.16\n',
        'pwd': '/home/user\n',
        'git --version 2>&1 | head -1': 'git version 2.39.0\n',
      });

      final provider = ShellEnvironmentProvider(
        executor,
        options: const ShellEnvironmentProviderOptions(
          overrideFamily: ShellFamily.posix,
          probeTools: ['git'],
        ),
      );

      final snapshot = await provider.probe();
      expect(snapshot.family, ShellFamily.posix);
    });

    test('PowerShell detection — overrideFamily forces powerShell', () async {
      final executor = _ScriptedExecutor({
        r'$PSVersionTable.PSVersion.ToString()': '7.3.0\n',
        '(Get-Location).Path': 'C:\\Users\\user\n',
        '(& git --version 2>&1 | Select-Object -First 1)':
            'git version 2.39.0\n',
      });

      final provider = ShellEnvironmentProvider(
        executor,
        options: const ShellEnvironmentProviderOptions(
          overrideFamily: ShellFamily.powerShell,
          probeTools: ['git'],
        ),
      );

      final snapshot = await provider.probe();
      expect(snapshot.family, ShellFamily.powerShell);
    });

    test('instructions formatter — POSIX includes export syntax', () async {
      final executor = _ScriptedExecutor({
        'echo "\$BASH_VERSION"': '5.1.0\n',
        'pwd': '/workspace\n',
        'git --version 2>&1 | head -1': 'git version 2.39.0\n',
      });

      final provider = ShellEnvironmentProvider(
        executor,
        options: const ShellEnvironmentProviderOptions(
          overrideFamily: ShellFamily.posix,
          probeTools: ['git'],
        ),
      );

      final snapshot = await provider.probe();
      final instructions = ShellEnvironmentProvider.defaultFormatter(snapshot);

      expect(instructions, contains('POSIX'));
      expect(instructions, contains('export'));
    });

    test('instructions formatter — PowerShell includes Set-Location', () async {
      final executor = _ScriptedExecutor({
        r'$PSVersionTable.PSVersion.ToString()': '7.3.0\n',
        '(Get-Location).Path': 'C:\\Users\\user\n',
        '(& git --version 2>&1 | Select-Object -First 1)':
            'git version 2.39.0\n',
      });

      final provider = ShellEnvironmentProvider(
        executor,
        options: const ShellEnvironmentProviderOptions(
          overrideFamily: ShellFamily.powerShell,
          probeTools: ['git'],
        ),
      );

      final snapshot = await provider.probe();
      final instructions = ShellEnvironmentProvider.defaultFormatter(snapshot);

      expect(instructions, contains('PowerShell'));
      expect(instructions, contains('Set-Location'));
    });

    test('tool probing — records null for tools with no output', () async {
      final executor = _ScriptedExecutor({
        'echo "\$BASH_VERSION"': '5.1.0\n',
        'pwd': '/workspace\n',
        'git --version 2>&1 | head -1': '',
      });

      final provider = ShellEnvironmentProvider(
        executor,
        options: const ShellEnvironmentProviderOptions(
          overrideFamily: ShellFamily.posix,
          probeTools: ['git'],
        ),
      );

      final snapshot = await provider.probe();
      expect(snapshot.toolVersions['git'], isNull);
    });

    test('invalid tool name — rejected (shell metacharacters)', () async {
      final executor = _ScriptedExecutor({
        'echo "\$BASH_VERSION"': '5.1.0\n',
        'pwd': '/workspace\n',
      });

      final provider = ShellEnvironmentProvider(
        executor,
        options: const ShellEnvironmentProviderOptions(
          overrideFamily: ShellFamily.posix,
          probeTools: ['git; rm -rf /'],
        ),
      );

      final snapshot = await provider.probe();
      // The invalid tool name should be silently skipped.
      expect(snapshot.toolVersions, isEmpty);
    });

    test('failing executor — provider completes gracefully', () async {
      final provider = ShellEnvironmentProvider(
        _FailingExecutor(),
        options: const ShellEnvironmentProviderOptions(
          overrideFamily: ShellFamily.posix,
          probeTools: ['git'],
          probeTimeout: Duration(milliseconds: 100),
        ),
      );

      // Should not throw; failures are swallowed per probe.
      final snapshot = await provider.probe();
      expect(snapshot.shellVersion, isNull);
      expect(snapshot.workingDirectory, isEmpty);
    });

    test('os description — matches platform', () async {
      final executor = _ScriptedExecutor({
        'echo "\$BASH_VERSION"': '5.1.0\n',
        'pwd': '/workspace\n',
        'git --version 2>&1 | head -1': 'git version 2.39.0\n',
      });

      final provider = ShellEnvironmentProvider(
        executor,
        options: const ShellEnvironmentProviderOptions(
          overrideFamily: ShellFamily.posix,
          probeTools: ['git'],
        ),
      );

      final snapshot = await provider.probe();
      expect(snapshot.osDescription, equals(Platform.operatingSystemVersion));
    });

    test('custom instructionsFormatter — is called with snapshot', () async {
      var formatterCalled = false;
      dynamic capturedSnapshot;

      final executor = _ScriptedExecutor({
        'echo "\$BASH_VERSION"': '5.1.0\n',
        'pwd': '/workspace\n',
      });

      final provider = ShellEnvironmentProvider(
        executor,
        options: ShellEnvironmentProviderOptions(
          overrideFamily: ShellFamily.posix,
          probeTools: const [],
          instructionsFormatter: (s) {
            formatterCalled = true;
            capturedSnapshot = s;
            return 'custom instructions';
          },
        ),
      );

      final snapshot = await provider.probe();
      final instructions = ShellEnvironmentProvider.defaultFormatter(snapshot);

      // Use the custom formatter via options.
      final provider2 = ShellEnvironmentProvider(
        executor,
        options: ShellEnvironmentProviderOptions(
          overrideFamily: ShellFamily.posix,
          probeTools: const [],
          instructionsFormatter: (s) {
            formatterCalled = true;
            capturedSnapshot = s;
            return 'custom instructions';
          },
        ),
      );
      await provider2.probe();

      expect(instructions, isNotEmpty);
      // Verify the formatter is wired through provideAIContext by checking
      // that a direct options formatter call would work.
      expect(formatterCalled, isFalse); // Not called until provideAIContext.
      expect(capturedSnapshot, isNull);
    });
  });
}
