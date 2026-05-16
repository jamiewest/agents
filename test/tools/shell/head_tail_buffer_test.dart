import 'dart:convert';

import 'package:test/test.dart';

import 'package:agents/src/tools/shell/head_tail_buffer.dart';

void main() {
  group('HeadTailBuffer', () {
    test('below cap — round-trips exact input', () {
      final buf = HeadTailBuffer(1024);
      buf.appendLine('hello');
      buf.appendLine('world');

      final (text, truncated) = buf.toFinalString();

      expect(truncated, isFalse);
      expect(text, equals('hello\nworld\n'));
    });

    test('many lines — stays bounded and retains head and tail', () {
      final buf = HeadTailBuffer(4096);
      for (var i = 0; i < 100000; i++) {
        buf.appendLine('line ${i.toString().padLeft(6, '0')}');
      }

      final (text, truncated) = buf.toFinalString();

      expect(truncated, isTrue);
      final byteCount = utf8.encode(text).length;
      expect(
        byteCount,
        lessThanOrEqualTo(4096 + 128),
        reason: 'Result was $byteCount bytes, expected <= ~${4096 + 128}',
      );
      expect(text, contains('line 000000'));
      expect(text, contains('[... truncated'));
      expect(text, contains('line 099999'));
    });

    test('huge single line — does not accumulate unbounded', () {
      final buf = HeadTailBuffer(1024);
      final chunk = 'x' * 10000;
      for (var i = 0; i < 100; i++) {
        buf.appendLine(chunk);
      }

      final (text, truncated) = buf.toFinalString();

      expect(truncated, isTrue);
      final byteCount = utf8.encode(text).length;
      expect(
        byteCount,
        lessThan(4096),
        reason: 'Result was $byteCount bytes, expected < 4096',
      );
    });

    test('multi-byte UTF-8 — respects byte budget and never splits runes', () {
      final buf = HeadTailBuffer(32);
      for (var i = 0; i < 200; i++) {
        buf.appendLine('🔥🔥🔥🔥🔥');
      }

      final (text, truncated) = buf.toFinalString();

      expect(truncated, isTrue);

      final roundTripped = utf8.decode(utf8.encode(text));
      expect(roundTripped, equals(text));
      expect(text, isNot(contains('�')));
    });

    test('odd cap — round-trips exactly at cap without dropping', () {
      // AppendLine adds a newline, so 5 chars + '\n' = 6 bytes, exactly at cap.
      const input = 'ABCDE';
      final buf = HeadTailBuffer(6);
      buf.appendLine(input);

      final (text, truncated) = buf.toFinalString();

      expect(truncated, isFalse);
      expect(text, equals('$input\n'));
    });

    test('odd cap — at cap, no silent data drop', () {
      // cap=5; AppendLine('ABCD') → 4 chars + newline = 5 bytes.
      final buf = HeadTailBuffer(5);
      buf.appendLine('ABCD');

      final (text, truncated) = buf.toFinalString();

      expect(truncated, isFalse);
      expect(text, equals('ABCD\n'));
    });
  });
}
