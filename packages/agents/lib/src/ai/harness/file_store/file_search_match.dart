/// Represents a match found within a file during a search operation.
class FileSearchMatch {
  FileSearchMatch();

  /// 1-based line number where the match was found.
  int lineNumber = 0;

  /// Content of the matching line.
  String line = '';
}
