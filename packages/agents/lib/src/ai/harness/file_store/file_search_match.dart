/// Represents a match found within a file during a search operation.
class FileSearchMatch {
  FileSearchMatch();

  /// 1-based line number where the match was found.
  ///
  /// It is a coordinate into `AgentFileStore.splitLines` of the same content
  /// `readFileAsync` returns, so it addresses the same lines the line-edit
  /// tools operate on.
  int lineNumber = 0;

  /// The matching line, verbatim.
  ///
  /// Implementers should report the line exactly as it appears in the file,
  /// keeping its own terminator (`\r\n`, `\n`, or a lone `\r`), except on a
  /// final line that the content does not terminate. Together with
  /// [lineNumber] addressing the same lines the line-edit tools use, that
  /// makes the value reusable as a literal replacement line without
  /// re-reading the file.
  String line = '';
}
