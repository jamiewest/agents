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

  /// Checks whether a file exists.
  Future<bool> fileExistsAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]);

  /// Searches for files whose content matches a regular expression pattern.
  Future<List<FileSearchResult>> searchFilesAsync(
    String directory,
    String regexPattern, [
    String? filePattern,
    CancellationToken? cancellationToken,
  ]);

  /// Ensures a directory exists, creating it if necessary.
  Future<void> createDirectoryAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]);
}
