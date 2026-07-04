import 'package:extensions/system.dart';

import 'file_search_result.dart';
import 'file_store_entry.dart';

/// Provides an abstract base class for file storage operations.
///
/// All paths are relative to an implementation-defined root. Implementations
/// may map these paths to a local file system, in-memory store, remote blob
/// storage, or other mechanisms. Paths use forward slashes as separators and
/// must not escape the root (e.g., via `..` segments). It is up to each
/// implementation to enforce this.
abstract class AgentFileStore {
  AgentFileStore();

  /// Writes content to a file, creating or overwriting it.
  Future<void> writeFileAsync(
    String path,
    String content, [
    CancellationToken? cancellationToken,
  ]);

  /// Reads the content of a file.
  Future<String?> readFileAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]);

  /// Deletes a file.
  Future<bool> deleteFileAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]);

  /// Lists files in a directory.
  Future<List<String>> listFilesAsync(
    String directory, [
    CancellationToken? cancellationToken,
  ]);

  /// Lists the direct children (files and subdirectories) of a directory.
  ///
  /// Use an empty string for the root. Subdirectories are listed before
  /// files.
  Future<List<FileStoreEntry>> listChildrenAsync(
    String directory, [
    CancellationToken? cancellationToken,
  ]);

  /// Checks whether a file exists.
  Future<bool> fileExistsAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]);

  /// Searches for files whose content matches a regular expression pattern.
  ///
  /// When [recursive] is `true`, files in subdirectories of [directory] are
  /// searched as well; result file names are paths relative to [directory]
  /// (using forward slashes). [filePattern] is a glob matched against each
  /// file's relative path.
  Future<List<FileSearchResult>> searchFilesAsync(
    String directory,
    String regexPattern, [
    String? filePattern,
    bool recursive = false,
    CancellationToken? cancellationToken,
  ]);

  /// Ensures a directory exists, creating it if necessary.
  Future<void> createDirectoryAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]);
}
