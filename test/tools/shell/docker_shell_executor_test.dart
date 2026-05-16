import 'package:extensions/ai.dart';
import 'package:test/test.dart';

import 'package:agents/src/tools/shell/container_user.dart';
import 'package:agents/src/tools/shell/docker_shell_executor.dart';
import 'package:agents/src/tools/shell/docker_shell_executor_options.dart';
import 'package:agents/src/tools/shell/shell_mode.dart';
import 'package:agents/src/tools/shell/shell_policy.dart';

void main() {
  // ── Argv builder tests (no Docker daemon required) ───────────────────────

  group('DockerShellExecutor.buildRunArgv', () {
    test('emits restrictive defaults', () {
      final argv = DockerShellExecutor.buildRunArgv(
        binary: 'docker',
        image: 'alpine:3.19',
        containerName: 'af-shell-test',
        user: ContainerUser.defaultUser,
        network: 'none',
        memoryBytes: 256 * 1024 * 1024,
        pidsLimit: 64,
        workdir: '/workspace',
        hostWorkdir: null,
        mountReadonly: true,
        readOnlyRoot: true,
        extraEnv: null,
        extraArgs: null,
      );

      expect(argv[0], equals('docker'));
      expect(argv[1], equals('run'));
      expect(argv, contains('-d'));
      expect(argv, contains('--rm'));
      expect(argv, contains('--network'));
      expect(argv, contains('none'));
      expect(argv, contains('--cap-drop'));
      expect(argv, contains('ALL'));
      expect(argv, contains('--security-opt'));
      expect(argv, contains('no-new-privileges'));
      expect(argv, contains('--read-only'));
      expect(argv, contains('--tmpfs'));
      // Image and sleep sentinel at the end.
      expect(argv[argv.length - 3], equals('alpine:3.19'));
      expect(argv[argv.length - 2], equals('sleep'));
      expect(argv[argv.length - 1], equals('infinity'));
    });

    test('host workdir — adds volume mount with rw', () {
      final argv = DockerShellExecutor.buildRunArgv(
        binary: 'docker',
        image: 'alpine:3.19',
        containerName: 'af-shell-test',
        user: const ContainerUser('1000', '1000'),
        network: 'none',
        memoryBytes: 256 * 1024 * 1024,
        pidsLimit: 64,
        workdir: '/workspace',
        hostWorkdir: '/tmp/proj',
        mountReadonly: false,
        readOnlyRoot: false,
        extraEnv: null,
        extraArgs: null,
      );

      final idx = argv.indexOf('-v');
      expect(idx, greaterThanOrEqualTo(0), reason: 'expected -v flag');
      expect(argv[idx + 1], equals('/tmp/proj:/workspace:rw'));
      expect(argv, isNot(contains('--read-only')));
    });

    test('host workdir — defaults to read-only', () {
      final argv = DockerShellExecutor.buildRunArgv(
        binary: 'docker',
        image: 'alpine:3.19',
        containerName: 'x',
        user: const ContainerUser('1000', '1000'),
        network: 'none',
        memoryBytes: 256 * 1024 * 1024,
        pidsLimit: 64,
        workdir: '/workspace',
        hostWorkdir: '/host/path',
        mountReadonly: true,
        readOnlyRoot: true,
        extraEnv: null,
        extraArgs: null,
      );

      final idx = argv.indexOf('-v');
      expect(argv[idx + 1], equals('/host/path:/workspace:ro'));
    });

    test('env and extraArgs — are appended', () {
      final env = {'LOG': '1', 'MODE': 'ci'};
      final extra = ['--label', 'owner=test'];

      final argv = DockerShellExecutor.buildRunArgv(
        binary: 'docker',
        image: 'alpine:3.19',
        containerName: 'x',
        user: const ContainerUser('1000', '1000'),
        network: 'none',
        memoryBytes: 256 * 1024 * 1024,
        pidsLimit: 64,
        workdir: '/workspace',
        hostWorkdir: null,
        mountReadonly: true,
        readOnlyRoot: true,
        extraEnv: env,
        extraArgs: extra,
      );

      expect(argv, contains('LOG=1'));
      expect(argv, contains('MODE=ci'));
      expect(argv, contains('--label'));
      expect(argv, contains('owner=test'));
    });
  });

  group('DockerShellExecutor.buildExecArgv', () {
    test('emits bash with --noprofile --norc', () {
      final argv = DockerShellExecutor.buildExecArgv('docker', 'af-shell-x');
      expect(
        argv,
        equals([
          'docker',
          'exec',
          '-i',
          'af-shell-x',
          'bash',
          '--noprofile',
          '--norc',
        ]),
      );
    });
  });

  // ── Constructor tests ─────────────────────────────────────────────────────

  group('DockerShellExecutor — constructor', () {
    test('generates unique container names', () async {
      final t1 = DockerShellExecutor(
        const DockerShellExecutorOptions(mode: ShellMode.stateless),
      );
      final t2 = DockerShellExecutor(
        const DockerShellExecutorOptions(mode: ShellMode.stateless),
      );
      await t1.dispose();
      await t2.dispose();
      expect(t1.containerName, startsWith('af-shell-'));
      expect(t2.containerName, startsWith('af-shell-'));
      expect(t1.containerName, isNot(equals(t2.containerName)));
    });

    test('respects explicit container name', () async {
      final t = DockerShellExecutor(
        const DockerShellExecutorOptions(
          containerName: 'my-explicit-name',
          mode: ShellMode.stateless,
        ),
      );
      await t.dispose();
      expect(t.containerName, equals('my-explicit-name'));
    });
  });

  // ── AI function tests ─────────────────────────────────────────────────────

  group('DockerShellExecutor.asAIFunction', () {
    test('default — is approval-gated', () async {
      final t = DockerShellExecutor(
        const DockerShellExecutorOptions(mode: ShellMode.stateless),
      );
      final fn = t.asAIFunction();
      await t.dispose();
      expect(fn, isA<ApprovalRequiredAIFunction>());
      expect(fn.name, equals('run_shell'));
    });

    test('requireApproval: true — wraps in ApprovalRequiredAIFunction', () async {
      final t = DockerShellExecutor(
        const DockerShellExecutorOptions(mode: ShellMode.stateless),
      );
      final fn = t.asAIFunction(requireApproval: true);
      await t.dispose();
      expect(fn, isA<ApprovalRequiredAIFunction>());
    });

    test('requireApproval: false — returns plain function', () async {
      final t = DockerShellExecutor(
        const DockerShellExecutorOptions(mode: ShellMode.stateless),
      );
      final fn = t.asAIFunction(requireApproval: false);
      await t.dispose();
      expect(fn, isNot(isA<ApprovalRequiredAIFunction>()));
    });
  });

  // ── isAvailableAsync ──────────────────────────────────────────────────────

  group('DockerShellExecutor.isAvailableAsync', () {
    test('non-existent binary — returns false', () async {
      final ok = await DockerShellExecutor.isAvailableAsync(
        binary: 'definitely-not-a-real-binary-xyz123',
      );
      expect(ok, isFalse);
    });
  });

  // ── Policy rejection (no Docker needed) ──────────────────────────────────

  group('DockerShellExecutor — policy', () {
    test('rejected command — throws ShellCommandRejectedException', () async {
      final t = DockerShellExecutor(DockerShellExecutorOptions(
        mode: ShellMode.stateless,
        policy: ShellPolicy(denyList: [r'\brm\s+-rf?\s+[\/]']),
      ));
      await expectLater(
        t.runAsync('rm -rf /'),
        throwsA(isA<ShellCommandRejectedException>()),
      );
      await t.dispose();
    });
  });
}
