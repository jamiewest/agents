import 'package:extensions/system.dart';
import 'file_search_result.dart';

/// Provides an abstract base class for file storage operations.
///
/// Remarks: All paths are relative to an implementation-defined root.
/// Implementations may map these paths to a local file system, in-memory
/// store, remote blob storage, or other mechanisms. Paths use forward slashes
/// as separators and must not escape the root (e.g., via `..` segments). It
/// is up to each implementation to ensure that this is enforced.
abstract class AgentFileStore {
  AgentFileStore();

  /// Writes content to a file, creating or overwriting it.
  ///
  /// Returns: A task representing the asynchronous operation.
  ///
  /// [path] The relative path of the file to write.
  ///
  /// [content] The content to write to the file.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future writeFile(
    String path,
    String content, {
    CancellationToken? cancellationToken,
  });

  /// Reads the content of a file.
  ///
  /// Returns: The file content, or `null` if the file does not exist.
  ///
  /// [path] The relative path of the file to read.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<String?> readFile(String path, {CancellationToken? cancellationToken});

  /// Deletes a file.
  ///
  /// Returns: `true` if the file was deleted; `false` if it did not exist.
  ///
  /// [path] The relative path of the file to delete.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<bool> deleteFile(String path, {CancellationToken? cancellationToken});

  /// Lists files in a directory.
  ///
  /// Returns: A list of file names in the specified directory (direct children
  /// only).
  ///
  /// [directory] The relative path of the directory to list. Use an empty
  /// String for the root.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<List<String>> listFiles(
    String directory, {
    CancellationToken? cancellationToken,
  });

  /// Checks whether a file exists.
  ///
  /// Returns: `true` if the file exists; otherwise, `false`.
  ///
  /// [path] The relative path of the file to check.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<bool> fileExists(String path, {CancellationToken? cancellationToken});

  /// Searches for files whose content matches a regular expression pattern.
  ///
  /// Returns: A list of search results with matching file names, snippets, and
  /// matching lines.
  ///
  /// [directory] The relative path of the directory to search. Use an empty
  /// String for the root.
  ///
  /// [regexPattern] A regular expression pattern to match against file
  /// contents. The pattern is matched case-insensitively. For example,
  /// `"error|warning"` matches lines containing "error" or "warning".
  ///
  /// [filePattern] An optional glob pattern to filter which files are searched
  /// (e.g., `"*.md"`, `"research*"`). When `null`, all files in the directory
  /// are searched. Uses standard glob syntax from [Matcher].
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<List<FileSearchResult>> searchFiles(
    String directory,
    String regexPattern, {
    String? filePattern,
    CancellationToken? cancellationToken,
  });

  /// Ensures a directory exists, creating it if necessary.
  ///
  /// Returns: A task representing the asynchronous operation.
  ///
  /// [path] The relative path of the directory to create.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future createDirectory(String path, {CancellationToken? cancellationToken});
}
