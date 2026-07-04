import 'file_line_edit.dart';

/// Helpers shared by the file access and file memory providers for the
/// `replace` and `replace_lines` tools.
class FileEditor {
  FileEditor._();

  /// Replaces occurrences of [oldString] with [newString] in [content],
  /// returning the new content and the number of replacements made.
  ///
  /// Throws an [ArgumentError] when [oldString] is empty, is not found, or
  /// occurs more than once while [replaceAll] is `false`.
  static (String content, int count) applyReplace(
    String content,
    String oldString,
    String newString, {
    required bool replaceAll,
  }) {
    if (oldString.isEmpty) {
      throw ArgumentError('old_string must not be empty.');
    }

    final count = _countOccurrences(content, oldString);
    if (count == 0) {
      throw ArgumentError("old_string not found: '$oldString'.");
    }

    if (count > 1 && !replaceAll) {
      throw ArgumentError(
        'old_string occurs $count times; pass replace_all=true to replace '
        'all, or provide a more specific old_string.',
      );
    }

    return (content.replaceAll(oldString, newString), count);
  }

  /// Applies literal (1-based) line replacements to [content].
  ///
  /// Each edit's [FileLineEdit.newLine] is treated as the literal replacement
  /// text for the targeted line, including any trailing newline the caller
  /// wants to keep — the editor does not add one. An empty
  /// [FileLineEdit.newLine] deletes the line entirely, including its line
  /// break.
  ///
  /// Throws an [ArgumentError] when [edits] is empty, any line number is out
  /// of range, or a line number is targeted more than once.
  static String applyReplaceLines(String content, List<FileLineEdit> edits) {
    if (edits.isEmpty) {
      throw ArgumentError('At least one line edit must be provided.');
    }

    final lines = _splitLinesKeepEnds(content);

    final seen = <int>{};
    for (final edit in edits) {
      if (!seen.add(edit.lineNumber)) {
        throw ArgumentError(
          'Duplicate line_number ${edit.lineNumber} in '
          'edits.',
        );
      }
      if (edit.lineNumber < 1 || edit.lineNumber > lines.length) {
        throw ArgumentError(
          'line_number ${edit.lineNumber} is out of range (file has '
          '${lines.length} lines).',
        );
      }
    }

    for (final edit in edits) {
      // An empty replacement removes the line (content and its line break);
      // otherwise the replacement is written verbatim, so the caller controls
      // any trailing newline.
      lines[edit.lineNumber - 1] = edit.newLine;
    }

    return lines.join();
  }

  static int _countOccurrences(String content, String value) {
    var count = 0;
    var index = content.indexOf(value);
    while (index >= 0) {
      count++;
      index = content.indexOf(value, index + value.length);
    }
    return count;
  }

  /// Splits content into lines, keeping each line's trailing newline
  /// (`\r\n`, `\n`, or a lone `\r`) attached. The final line has no
  /// terminator when the content does not end with a newline.
  static List<String> _splitLinesKeepEnds(String content) {
    final lines = <String>[];
    var start = 0;
    for (var i = 0; i < content.length; i++) {
      final c = content[i];
      if (c == '\n') {
        lines.add(content.substring(start, i + 1));
        start = i + 1;
      } else if (c == '\r') {
        // Treat "\r\n" as a single terminator; a lone "\r" also terminates a
        // line.
        final end = (i + 1 < content.length && content[i + 1] == '\n')
            ? i + 2
            : i + 1;
        lines.add(content.substring(start, end));
        i = end - 1;
        start = end;
      }
    }

    if (start < content.length) {
      lines.add(content.substring(start));
    }

    return lines;
  }
}
