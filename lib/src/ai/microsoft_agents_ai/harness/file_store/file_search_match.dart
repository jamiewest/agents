/// Represents a match found within a file during a search operation.
class FileSearchMatch {
  FileSearchMatch();

  /// Gets or sets the 1-based line number where the match was found.
  int lineNumber = 0;

  /// Gets or sets the content of the matching line.
  String line = '';
}
