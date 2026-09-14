import 'agent_file_store.dart';
import 'file_line_edit.dart';

/// Helpers shared by the file access and file memory providers for the
/// `replace`, `replace_lines`, and `read_lines` tools, and by the file stores
/// for `grep`.
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

    final lines = splitLinesKeepEnds(content);

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

      // When the caller says what it expects to be there, a mismatch means
      // the number is stale or was never right. Refusing turns a silent
      // overwrite of the wrong line into an error, and is the one check that
      // also covers the file changing under us.
      final expectedLine = edit.expectedLine;
      if (expectedLine != null) {
        final actual = trimLineTerminator(lines[edit.lineNumber - 1]);
        if (actual != trimLineTerminator(expectedLine)) {
          throw ArgumentError(
            'line_number ${edit.lineNumber} does not match the expected text. '
            'Re-read the file to get current line numbers.',
          );
        }
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

  /// Returns the 1-based inclusive `[startLine, endLine]` slice of [content],
  /// with each line's terminator kept attached.
  ///
  /// An [endLine] past the last line is clamped, and omitting it reads to the
  /// end of the content.
  ///
  /// Throws an [ArgumentError] when either bound is not positive, when
  /// [endLine] precedes [startLine], or when [startLine] is past the last
  /// line.
  static List<String> sliceLines(String content, int startLine, int? endLine) {
    final lines = splitLinesKeepEnds(content);
    final total = lines.length;

    // These messages reach the model as the tool's failure text, so they name
    // the arguments as the tool schema exposes them (startLine/endLine), not
    // in snake_case.
    if (startLine < 1) {
      throw ArgumentError(
        'startLine must be a positive integer, got $startLine.',
      );
    }

    if (endLine != null && endLine < 1) {
      throw ArgumentError('endLine must be a positive integer, got $endLine.');
    }

    if (endLine != null && endLine < startLine) {
      throw ArgumentError(
        'endLine ($endLine) must not be less than startLine ($startLine).',
      );
    }

    if (startLine > total) {
      throw ArgumentError(
        'startLine $startLine is out of range (file has $total lines).',
      );
    }

    // Clamping endLine rather than failing keeps "read from here to the end"
    // a single call.
    final lastLine = endLine == null
        ? total
        : (endLine < total ? endLine : total);
    return lines.sublist(startLine - 1, lastLine);
  }

  /// Returns [line] without its trailing `\r\n`, `\n` or lone `\r`.
  static String trimLineTerminator(String line) =>
      line.substring(0, lineContentLength(line));

  /// Returns the length of [line] up to but excluding the `\r\n`, `\n`, or
  /// lone `\r` that terminates it, so search patterns are matched against a
  /// line's text rather than its line break.
  ///
  /// Leaving any part of the terminator in range would make an end-anchored
  /// pattern such as `match$` fail on a CRLF or lone-CR line whose text is
  /// exactly `match`.
  static int lineContentLength(String line) {
    if (line.endsWith('\r\n')) {
      return line.length - 2;
    }
    return (line.endsWith('\n') || line.endsWith('\r'))
        ? line.length - 1
        : line.length;
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
  ///
  /// This is the single definition of a "line" for the line-edit tools, so
  /// the line numbers reported by `grep` address the same lines that
  /// `replace_lines` edits. A store supplying its own
  /// [AgentFileStore.searchFilesAsync] is expected to number by this split;
  /// nothing enforces that at runtime, so an implementation that numbers
  /// differently edits the wrong line silently.
  static List<String> splitLinesKeepEnds(String content) {
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
