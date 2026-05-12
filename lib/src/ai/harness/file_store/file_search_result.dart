import 'file_search_match.dart';

/// Represents a result from searching files, containing the file name, a
/// content snippet, and matching lines.
class FileSearchResult {
  FileSearchResult();

  /// Name of the file that matched the search.
  String fileName = '';

  /// Snippet of content from the file around the first match.
  String snippet = '';

  /// Lines where matches were found.
  List<FileSearchMatch> matchingLines = [];
}
