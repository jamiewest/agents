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

  group('FileEditor.sliceLines', () {
    const content = 'one\ntwo\nthree\nfour';

    test('returns the inclusive range with terminators attached', () {
      expect(FileEditor.sliceLines(content, 2, 3), ['two\n', 'three\n']);
    });

    test('reads to the end when endLine is omitted', () {
      expect(FileEditor.sliceLines(content, 3, null), ['three\n', 'four']);
    });

    test('clamps an endLine past the last line', () {
      expect(FileEditor.sliceLines(content, 4, 99), ['four']);
    });

    test('splits on CRLF and a lone CR', () {
      expect(FileEditor.sliceLines('a\r\nb\rc', 1, 3), ['a\r\n', 'b\r', 'c']);
    });

    test('rejects a non-positive startLine', () {
      expect(
        () => FileEditor.sliceLines(content, 0, null),
        throwsArgumentError,
      );
    });

    test('rejects a non-positive endLine', () {
      expect(() => FileEditor.sliceLines(content, 1, 0), throwsArgumentError);
    });

    test('rejects an endLine before startLine', () {
      expect(() => FileEditor.sliceLines(content, 3, 2), throwsArgumentError);
    });

    test('rejects a startLine past the last line', () {
      expect(
        () => FileEditor.sliceLines(content, 5, null),
        throwsArgumentError,
      );
    });
  });

  group('FileEditor.lineContentLength', () {
    test('excludes the terminator', () {
      expect(FileEditor.lineContentLength('abc\r\n'), 3);
      expect(FileEditor.lineContentLength('abc\n'), 3);
      expect(FileEditor.lineContentLength('abc\r'), 3);
      expect(FileEditor.lineContentLength('abc'), 3);
    });

    test('trimLineTerminator drops each terminator form', () {
      expect(FileEditor.trimLineTerminator('abc\r\n'), 'abc');
      expect(FileEditor.trimLineTerminator('abc\r'), 'abc');
      expect(FileEditor.trimLineTerminator('abc'), 'abc');
    });
  });

  group('FileEditor expected_line', () {
    test('applies the edit when the expected text matches', () {
      final result = FileEditor.applyReplaceLines('a\nb\nc\n', [
        FileLineEdit(lineNumber: 2, newLine: 'B\n', expectedLine: 'b'),
      ]);

      expect(result, 'a\nB\nc\n');
    });

    test('ignores the trailing terminator in the comparison', () {
      final result = FileEditor.applyReplaceLines('a\nb\nc\n', [
        FileLineEdit(lineNumber: 2, newLine: 'B\n', expectedLine: 'b\n'),
      ]);

      expect(result, 'a\nB\nc\n');
    });

    test('rejects the edit when the expected text does not match', () {
      expect(
        () => FileEditor.applyReplaceLines('a\nb\nc\n', [
          FileLineEdit(lineNumber: 2, newLine: 'B\n', expectedLine: 'stale'),
        ]),
        throwsArgumentError,
      );
    });

    test('leaves content untouched when any edit is rejected', () {
      const content = 'a\nb\nc\n';
      expect(
        () => FileEditor.applyReplaceLines(content, [
          FileLineEdit(lineNumber: 1, newLine: 'A\n'),
          FileLineEdit(lineNumber: 2, newLine: 'B\n', expectedLine: 'stale'),
        ]),
        throwsArgumentError,
      );
      expect(content, 'a\nb\nc\n');
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
        'expected_line': 'goodbye',
      });

      expect(edit.expectedLine, 'goodbye');
      expect(edit.toJson(), const {
        'line_number': 4,
        'new_line': 'hello\n',
        'expected_line': 'goodbye',
      });
    });
  });
}
