import 'package:agents/src/ai/harness/file_store/file_editor.dart';
import 'package:agents/src/ai/harness/file_store/file_line_edit.dart';
import 'package:test/test.dart';

void main() {
  group('FileEditor.applyReplace', () {
    test('replaces a unique occurrence', () {
      final (content, count) = FileEditor.applyReplace(
        'hello world',
        'world',
        'dart',
        replaceAll: false,
      );

      expect(content, 'hello dart');
      expect(count, 1);
    });

    test('replaces all occurrences when replaceAll is true', () {
      final (content, count) = FileEditor.applyReplace(
        'a b a b a',
        'a',
        'c',
        replaceAll: true,
      );

      expect(content, 'c b c b c');
      expect(count, 3);
    });

    test('throws on empty old string', () {
      expect(
        () => FileEditor.applyReplace('x', '', 'y', replaceAll: false),
        throwsArgumentError,
      );
    });

    test('throws when old string is not found', () {
      expect(
        () => FileEditor.applyReplace('x', 'missing', 'y', replaceAll: false),
        throwsArgumentError,
      );
    });

    test('throws on ambiguous old string without replaceAll', () {
      expect(
        () => FileEditor.applyReplace('a a', 'a', 'b', replaceAll: false),
        throwsArgumentError,
      );
    });
  });

  group('FileEditor.applyReplaceLines', () {
    test('replaces a line keeping surrounding line endings', () {
      final result = FileEditor.applyReplaceLines('one\ntwo\nthree\n', [
        FileLineEdit(lineNumber: 2, newLine: 'TWO\n'),
      ]);

      expect(result, 'one\nTWO\nthree\n');
    });

    test('empty replacement deletes the line and its break', () {
      final result = FileEditor.applyReplaceLines('one\ntwo\nthree\n', [
        FileLineEdit(lineNumber: 2, newLine: ''),
      ]);

      expect(result, 'one\nthree\n');
    });

    test('handles CRLF and missing trailing newline', () {
      final result = FileEditor.applyReplaceLines('one\r\ntwo\r\nthree', [
        FileLineEdit(lineNumber: 3, newLine: 'THREE'),
      ]);

      expect(result, 'one\r\ntwo\r\nTHREE');
    });

    test('applies multiple edits by line number', () {
      final result = FileEditor.applyReplaceLines('a\nb\nc\n', [
        FileLineEdit(lineNumber: 3, newLine: 'C\n'),
        FileLineEdit(lineNumber: 1, newLine: 'A\n'),
      ]);

      expect(result, 'A\nb\nC\n');
    });

    test('throws on empty edits, out-of-range, and duplicates', () {
      expect(
        () => FileEditor.applyReplaceLines('a\n', []),
        throwsArgumentError,
      );
      expect(
        () => FileEditor.applyReplaceLines('a\n', [
          FileLineEdit(lineNumber: 2, newLine: 'x'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => FileEditor.applyReplaceLines('a\nb\n', [
          FileLineEdit(lineNumber: 1, newLine: 'x\n'),
          FileLineEdit(lineNumber: 1, newLine: 'y\n'),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('FileEditor.applyReplaceLines expectedLine', () {
    test('applies the edit when the expected text matches', () {
      final result = FileEditor.applyReplaceLines('one\ntwo\nthree\n', [
        FileLineEdit(lineNumber: 2, newLine: 'TWO\n', expectedLine: 'two'),
      ]);

      expect(result, 'one\nTWO\nthree\n');
    });

    test('ignores the line terminator when comparing', () {
      final result = FileEditor.applyReplaceLines('one\r\ntwo\r\n', [
        FileLineEdit(
          lineNumber: 2,
          newLine: 'TWO\r\n',
          expectedLine: 'two\r\n',
        ),
      ]);

      expect(result, 'one\r\nTWO\r\n');
    });

    test('refuses the edit when the expected text does not match', () {
      expect(
        () => FileEditor.applyReplaceLines('one\ntwo\n', [
          FileLineEdit(lineNumber: 2, newLine: 'TWO\n', expectedLine: 'stale'),
        ]),
        throwsArgumentError,
      );
    });

    test('leaves the content untouched when one edit is refused', () {
      const content = 'one\ntwo\nthree\n';

      expect(
        () => FileEditor.applyReplaceLines(content, [
          FileLineEdit(lineNumber: 1, newLine: 'ONE\n'),
          FileLineEdit(
            lineNumber: 3,
            newLine: 'THREE\n',
            expectedLine: 'stale',
          ),
        ]),
        throwsArgumentError,
      );
      expect(content, 'one\ntwo\nthree\n');
    });
  });

  group('FileEditor.sliceLines', () {
    test('returns the inclusive range with terminators attached', () {
      final lines = FileEditor.sliceLines('a\nb\nc\nd\n', 2, 3);

      expect(lines, ['b\n', 'c\n']);
    });

    test('reads to the end when endLine is omitted', () {
      final lines = FileEditor.sliceLines('a\nb\nc', 2, null);

      expect(lines, ['b\n', 'c']);
    });

    test('clamps an endLine past the last line', () {
      final lines = FileEditor.sliceLines('a\nb\n', 1, 99);

      expect(lines, ['a\n', 'b\n']);
    });

    test('splits on a lone carriage return', () {
      final lines = FileEditor.sliceLines('a\rb\rc', 1, 2);

      expect(lines, ['a\r', 'b\r']);
    });

    test('rejects a non-positive startLine', () {
      expect(() => FileEditor.sliceLines('a\n', 0, null), throwsArgumentError);
    });

    test('rejects a non-positive endLine', () {
      expect(() => FileEditor.sliceLines('a\n', 1, 0), throwsArgumentError);
    });

    test('rejects an endLine before startLine', () {
      expect(() => FileEditor.sliceLines('a\nb\n', 2, 1), throwsArgumentError);
    });

    test('rejects a startLine past the last line', () {
      expect(() => FileEditor.sliceLines('a\n', 2, null), throwsArgumentError);
    });
  });

  group('FileEditor.lineContentLength', () {
    test('excludes each terminator shape', () {
      expect(FileEditor.lineContentLength('match\r\n'), 5);
      expect(FileEditor.lineContentLength('match\n'), 5);
      expect(FileEditor.lineContentLength('match\r'), 5);
      expect(FileEditor.lineContentLength('match'), 5);
    });

    test('trimLineTerminator strips only the terminator', () {
      expect(FileEditor.trimLineTerminator('match\r\n'), 'match');
      expect(FileEditor.trimLineTerminator('match\r'), 'match');
      expect(FileEditor.trimLineTerminator('match'), 'match');
    });
  });

  group('FileLineEdit JSON', () {
    test('round-trips the wire shape', () {
      final edit = FileLineEdit.fromJson(const {
        'line_number': 4,
        'new_line': 'hello\n',
      });

      expect(edit.lineNumber, 4);
      expect(edit.newLine, 'hello\n');
      expect(edit.expectedLine, isNull);
      expect(edit.toJson(), const {'line_number': 4, 'new_line': 'hello\n'});
    });

    test('round-trips expected_line when present', () {
      final edit = FileLineEdit.fromJson(const {
        'line_number': 4,
        'new_line': 'hello\n',
        'expected_line': 'old',
      });

      expect(edit.expectedLine, 'old');
      expect(edit.toJson(), const {
        'line_number': 4,
        'new_line': 'hello\n',
        'expected_line': 'old',
      });
    });
  });
}
