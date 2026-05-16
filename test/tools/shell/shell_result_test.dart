import 'package:test/test.dart';

import 'package:agents/src/tools/shell/shell_result.dart';

void main() {
  group('ShellResult.formatForModel', () {
    test('success — includes stdout and exit code', () {
      const r = ShellResult(
        stdout: 'hello\n',
        stderr: '',
        exitCode: 0,
        duration: Duration(milliseconds: 5),
      );
      final s = r.formatForModel();
      expect(s, contains('hello'));
      expect(s, contains('exit_code: 0'));
      expect(s, isNot(contains('stderr:')));
      expect(s, isNot(contains('[stdout truncated]')));
      expect(s, isNot(contains('[command timed out]')));
    });

    test('empty stdout — omits stdout block, only exit code', () {
      const r = ShellResult(
        stdout: '',
        stderr: '',
        exitCode: 0,
        duration: Duration.zero,
      );
      final s = r.formatForModel();
      expect(s, equals('exit_code: 0'));
    });

    test('non-empty stderr — includes stderr label', () {
      const r = ShellResult(
        stdout: '',
        stderr: 'boom\n',
        exitCode: 1,
        duration: Duration.zero,
      );
      final s = r.formatForModel();
      expect(s, contains('stderr: boom'));
      expect(s, contains('exit_code: 1'));
    });

    test('truncated — appends truncated marker inside stdout block', () {
      const r = ShellResult(
        stdout: 'partial-output',
        stderr: '',
        exitCode: 0,
        duration: Duration.zero,
        truncated: true,
      );
      final s = r.formatForModel();
      expect(s, contains('[stdout truncated]'));
    });

    test('timed out — appends timed-out marker', () {
      const r = ShellResult(
        stdout: '',
        stderr: '',
        exitCode: 124,
        duration: Duration(seconds: 30),
        timedOut: true,
      );
      final s = r.formatForModel();
      expect(s, contains('[command timed out]'));
      expect(s, contains('exit_code: 124'));
    });

    test('truncated but empty stdout — does not emit marker', () {
      // Marker is only emitted inside the stdout block; with empty stdout
      // there is no block to attach it to.
      const r = ShellResult(
        stdout: '',
        stderr: 'err\n',
        exitCode: 1,
        duration: Duration.zero,
        truncated: true,
      );
      final s = r.formatForModel();
      expect(s, isNot(contains('[stdout truncated]')));
      expect(s, contains('stderr: err'));
    });
  });
}
