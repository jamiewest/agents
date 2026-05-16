import 'dart:convert';

import 'package:test/test.dart';

import 'package:agents/src/tools/shell/shell_session.dart';

void main() {
  group('ShellSession.quotePosix', () {
    test('no special chars — wraps in single quotes', () {
      expect(ShellSession.quotePosix('/tmp/work'), equals("'/tmp/work'"));
    });

    test('dollar, backtick, command substitution — produces literal string', () {
      expect(
        ShellSession.quotePosix('/tmp/\$(touch /pwn)'),
        equals("'/tmp/\$(touch /pwn)'"),
      );
      expect(
        ShellSession.quotePosix('/tmp/\$VAR'),
        equals("'/tmp/\$VAR'"),
      );
      expect(
        ShellSession.quotePosix('/tmp/`id`'),
        equals("'/tmp/`id`'"),
      );
    });

    test('embedded single quote — closes and reopens', () {
      // POSIX: a'b → 'a'\''b'
      expect(ShellSession.quotePosix("a'b"), equals("'a'\\''b'"));
    });
  });

  group('ShellSession.quotePowerShell', () {
    test('dollar and subexpression — produces literal string', () {
      expect(
        ShellSession.quotePowerShell(r'C:\$(throw)'),
        equals(r"'C:\$(throw)'"),
      );
      expect(
        ShellSession.quotePowerShell(r'C:\$env:PATH'),
        equals(r"'C:\$env:PATH'"),
      );
    });

    test('embedded single quote — doubles it', () {
      // PowerShell: a'b → 'a''b'
      expect(ShellSession.quotePowerShell("a'b"), equals("'a''b'"));
    });
  });

  group('ShellSession.truncateHeadTail', () {
    test('under cap — returns input unchanged', () {
      const input = 'short';
      final (text, truncated) = ShellSession.truncateHeadTail(input, cap: 1024);
      expect(text, equals(input));
      expect(truncated, isFalse);
    });

    test('exactly at cap — returns input unchanged', () {
      final input = 'x' * 100;
      final (text, truncated) = ShellSession.truncateHeadTail(input, cap: 100);
      expect(text, equals(input));
      expect(truncated, isFalse);
    });

    test('over cap — truncates and includes marker', () {
      final input = 'HEAD${'x' * 1000}TAIL';
      final (text, truncated) = ShellSession.truncateHeadTail(input, cap: 20);
      expect(truncated, isTrue);
      expect(text, contains('[... truncated'));
      expect(text, contains('HEAD'));
      expect(text, contains('TAIL'));
      expect(text.length, lessThan(input.length));
    });

    test('empty string — returns empty', () {
      final (text, truncated) = ShellSession.truncateHeadTail('', cap: 10);
      expect(text, equals(''));
      expect(truncated, isFalse);
    });

    test('multi-byte UTF-8 — respects byte budget and rune boundaries', () {
      // Each 🔥 is 4 UTF-8 bytes; 50 of them = 200 bytes.
      final input = '🔥' * 50;
      expect(utf8.encode(input).length, equals(200));

      final (text, truncated) = ShellSession.truncateHeadTail(input, cap: 40);
      expect(truncated, isTrue);

      final roundTripped = utf8.decode(utf8.encode(text));
      expect(roundTripped, equals(text));

      // Byte budget: find marker, measure preserved bytes.
      final markerStart = text.indexOf('\n');
      final markerEnd = text.lastIndexOf('\n');
      final preserved =
          text.substring(0, markerStart) + text.substring(markerEnd + 1);
      expect(utf8.encode(preserved).length, lessThanOrEqualTo(40));
    });

    test('non-ASCII at boundary — does not produce replacement char', () {
      const input = 'AAAA🔥BBBBCCCC🔥DDDD';
      final (text, _) = ShellSession.truncateHeadTail(input, cap: 8);
      expect(text, isNot(contains('�')));
    });

    test('unpaired high surrogate — does not misalign byte count', () {
      // Build a string with a lone high surrogate.
      final input = 'AAAA${String.fromCharCode(0xD83D)}BBBB';
      final (text, _) = ShellSession.truncateHeadTail(input, cap: 6);
      // The function must complete and produce a valid round-trip result.
      final rt = utf8.decode(utf8.encode(text), allowMalformed: true);
      expect(rt, equals(text));
    });
  });
}
