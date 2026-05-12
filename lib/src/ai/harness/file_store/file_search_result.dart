import 'file_search_match.dart';

/// Represents a result from searching files, containing the file name, a
/// content snippet, and matching lines.
class FileSearchResult {
  FileSearchResult();

  /// Gets or sets the name of the file that matched the search.
  String fileName = '';

  /// Gets or sets a snippet of content from the file around the first match.
  String snippet = '';

  /// Gets or sets the lines where matches were found.
  List<FileSearchMatch> matchingLines = [];
}
