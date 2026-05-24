import 'package:test/test.dart';

import 'package:agents/src/tools/shell/shell_resolver.dart';

void main() {
  ResolvedShell resolveSingle(String binary) =>
      ShellResolver.resolveArgv([binary]);

  const shCommandArgv = ['-c', 'echo hi'];
  const bashCommandArgv = ['--noprofile', '--norc', '-c', 'echo hi'];
  const bashPersistentArgv = ['--noprofile', '--norc'];

  group('sh variants — stateless omits bash-only flags', () {
    for (final binary in [
      '/bin/sh',
      '/bin/dash',
      '/bin/ash',
      '/usr/bin/busybox',
      '/usr/bin/zsh',
      '/bin/ksh',
    ]) {
      test(binary, () {
        final argv = resolveSingle(binary).statelessArgvForCommand('echo hi');
        expect(argv, equals(shCommandArgv));
        expect(argv, isNot(contains('--noprofile')));
        expect(argv, isNot(contains('--norc')));
      });
    }
  });

  group('sh variants — persistent omits bash-only flags', () {
    for (final binary in [
      '/bin/sh',
      '/bin/dash',
      '/bin/ash',
      '/usr/bin/busybox',
      '/usr/bin/zsh',
      '/bin/ksh',
    ]) {
      test(binary, () {
        final argv = resolveSingle(binary).persistentArgv();
        expect(argv, isEmpty);
      });
    }
  });

  group('bash variants — stateless includes bash flags', () {
    for (final binary in ['/bin/bash', '/usr/local/bin/bash']) {
      test(binary, () {
        final argv = resolveSingle(binary).statelessArgvForCommand('echo hi');
        expect(argv, equals(bashCommandArgv));
      });
    }
  });

  group('bash variants — persistent includes bash flags', () {
    for (final binary in ['/bin/bash', '/usr/local/bin/bash']) {
      test(binary, () {
        final argv = resolveSingle(binary).persistentArgv();
        expect(argv, equals(bashPersistentArgv));
      });
    }
  });
}
