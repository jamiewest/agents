import 'dart:io';

import 'package:path/path.dart' as p;

import 'shell_family.dart';

enum _ShellKind { bash, powerShell, sh }

/// Resolves which shell binary to use and provides argv builders for both
/// stateless and persistent invocation modes.
class ShellResolver {
  ShellResolver._();

  /// Returns a [ResolvedShell] for the first existing candidate in
  /// [candidates]. Falls back to the first candidate if none exist on disk
  /// (useful in unit tests that pass synthetic paths).
  static ResolvedShell resolveArgv(List<String> candidates) {
    assert(candidates.isNotEmpty, 'candidates must not be empty');
    final found = candidates.firstWhere(
      (c) => _exists(c),
      orElse: () => candidates.first,
    );
    return ResolvedShell._fromBinary(found);
  }

  /// Returns the default candidate list for the current platform.
  static List<String> defaultCandidates() {
    if (Platform.isWindows) {
      return ['pwsh.exe', 'powershell.exe'];
    }
    return ['/bin/bash', '/bin/sh'];
  }

  static bool _exists(String path) {
    // Absolute paths: check directly.
    if (p.isAbsolute(path)) return File(path).existsSync();
    // Bare names: treat as found (resolved by PATH at spawn time).
    return true;
  }
}

/// A resolved shell binary together with its argv-building methods.
class ResolvedShell {
  ResolvedShell._(this.binary, this._kind, this.family);

  factory ResolvedShell._fromBinary(String binary) {
    final name = p.basename(binary).toLowerCase();
    final _ShellKind kind;
    final ShellFamily family;
    if (name == 'bash' || name == 'bash.exe') {
      kind = _ShellKind.bash;
      family = ShellFamily.posix;
    } else if (name == 'pwsh' ||
        name == 'powershell' ||
        name == 'pwsh.exe' ||
        name == 'powershell.exe') {
      kind = _ShellKind.powerShell;
      family = ShellFamily.powerShell;
    } else {
      kind = _ShellKind.sh;
      family = ShellFamily.posix;
    }
    return ResolvedShell._(binary, kind, family);
  }

  /// The resolved shell binary path.
  final String binary;

  /// The shell family (POSIX or PowerShell).
  final ShellFamily family;

  final _ShellKind _kind;

  /// Returns the argv for running [command] in a fresh subprocess.
  List<String> statelessArgvForCommand(String command) => switch (_kind) {
        _ShellKind.bash => ['--noprofile', '--norc', '-c', command],
        _ShellKind.powerShell => ['-NonInteractive', '-Command', command],
        _ShellKind.sh => ['-c', command],
      };

  /// Returns the argv for starting a persistent interactive shell.
  List<String> persistentArgv() => switch (_kind) {
        _ShellKind.bash => ['--noprofile', '--norc'],
        _ShellKind.powerShell => ['-NonInteractive', '-NoLogo'],
        _ShellKind.sh => [],
      };

  /// Returns `true` when persistent mode is supported for this shell.
  bool get supportsPersistent => _kind != _ShellKind.sh || _kind == _ShellKind.bash;
}
