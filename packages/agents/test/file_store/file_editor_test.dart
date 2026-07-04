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

  group('FileLineEdit JSON', () {
    test('round-trips the wire shape', () {
      final edit = FileLineEdit.fromJson(const {
        'line_number': 4,
        'new_line': 'hello\n',
      });

      expect(edit.lineNumber, 4);
      expect(edit.newLine, 'hello\n');
      expect(edit.toJson(), const {'line_number': 4, 'new_line': 'hello\n'});
    });
  });
}
