import 'dart:convert';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:math';
import 'package:extensions/system.dart';
import 'agent_file_store.dart';
import 'file_search_match.dart';
import 'file_search_result.dart';
import 'store_paths.dart';

/// A file-system-backed implementation of [AgentFileStore] that stores files
/// on disk under a configurable root directory.
///
/// Remarks: All paths passed to this store are resolved relative to the root
/// directory provided at construction time. Lexical path traversal attempts
/// (for example, via `..` segments or absolute paths) are rejected with an
/// [ArgumentException]. The root directory is created automatically if it
/// does not already exist.
class FileSystemAgentFileStore extends AgentFileStore {
  /// Initializes a new instance of the [FileSystemAgentFileStore] class.
  ///
  /// [rootDirectory] The root directory under which all files are stored.
  /// Created if it does not exist.
  FileSystemAgentFileStore(String rootDirectory) {
    rootDirectory;
    var fullRoot = p.canonicalize(rootDirectory);
    if (!fullRoot.endsWith(p.separator.toString()) &&
            !fullRoot.endsWith(
              '/'.toString(),
              ,
            ) ) {
      fullRoot += p.separator;
    }
    this._rootPath = fullRoot;
    Directory.createDirectory(fullRoot);
  }

  /// The canonical full path of the root directory, always ending with a
  /// directory separator.
  late final String _rootPath;

  @override
  Future writeFile(String path, String content, {CancellationToken? cancellationToken, }) async {
    var fullPath = this.resolveSafePath(path);
    var parentDir = p.dirname(fullPath);
    if (parentDir != null) {
      Directory.createDirectory(parentDir);
    }
    var writer = streamWriter(fullPath, false, const Utf8Codec());
    await writer.writeAsync(content);
  }

  @override
  Future<String?> readFile(String path, {CancellationToken? cancellationToken, }) async {
    var fullPath = this.resolveSafePath(path);
    if (!File.exists(fullPath)) {
      return null;
    }
    var reader = streamReader(fullPath, const Utf8Codec());
    return await reader.readToEndAsync();
  }

  @override
  Future<bool> deleteFile(String path, {CancellationToken? cancellationToken, }) {
    var fullPath = this.resolveSafePath(path);
    if (!File.exists(fullPath)) {
      return Future.value(false);
    }
    File.delete(fullPath);
    return Future.value(true);
  }

  @override
  Future<List<String>> listFiles(String directory, {CancellationToken? cancellationToken, }) {
    var fullDir = this.resolveSafeDirectoryPath(directory);
    if (!Directory.exists(fullDir)) {
      return Future.value<List<String>>([]);
    }
    var files = Directory.getFiles(fullDir)
            .map(p.basename)
            .where((name) => name != null)
            .toList();
    return Future.value<List<String>>(files!);
  }

  @override
  Future<bool> fileExists(String path, {CancellationToken? cancellationToken, }) {
    var fullPath = this.resolveSafePath(path);
    return Future.value(File.exists(fullPath));
  }

  @override
  Future<List<FileSearchResult>> searchFiles(
    String directory,
    String regexPattern,
    {String? filePattern, CancellationToken? cancellationToken, }
  ) async {
    var fullDir = this.resolveSafeDirectoryPath(directory);
    if (!Directory.exists(fullDir)) {
      return [];
    }
    var regex = regex(regexPattern, TimeSpan.fromSeconds(5));
    var matcher = filePattern != null ? StorePaths.createGlobMatcher(filePattern) : null;
    var results = List<FileSearchResult>();
    for (final filePath in Directory.getFiles(fullDir)) {
      var fileName = p.basename(filePath);
      if (fileName == null) {
        continue;
      }
      if (!StorePaths.matchesGlob(fileName, matcher)) {
        continue;
      }
      // Read file content.
      final fileContent = await File(filePath).readAsString();
      var lines = fileContent.split('\n');
      var matchingLines = List<FileSearchMatch>();
      var firstSnippet = null;
      var lineStartOffset = 0;
      for (var i = 0; i < lines.length; i++) {
        var match = regex.match(lines[i]);
        if (match.success) {
          matchingLines.add(fileSearchMatch());
          if (firstSnippet == null) {
            var charIndex = lineStartOffset + match.index;
            var snippetStart = max(0, charIndex - 50);
            var snippetEnd = min(fileContent.length, charIndex + match.value.length + 50);
            firstSnippet = fileContent.substring(snippetStart, snippetEnd - snippetStart);
          }
        }
        // Advance the offset past this line (including the '\n' separator).
                lineStartOffset += lines[i].length + 1;
      }
      if (matchingLines.length > 0) {
        results.add(fileSearchResult());
      }
    }
    return results;
  }

  @override
  Future createDirectory(String path, {CancellationToken? cancellationToken, }) {
    var fullPath = this.resolveSafeDirectoryPath(path);
    Directory.createDirectory(fullPath);
    return Task.value(null);
  }

  /// Resolves a relative file path to a safe absolute path under the root
  /// directory. Rejects paths that would escape the root via traversal or
  /// rooted paths.
  String resolveSafePath(String relativePath) {
    var normalized = StorePaths.normalizeRelativePath(relativePath);
    var nativePath = normalized.replaceAll('/', p.separator);
    var combined = p.join(this._rootPath, nativePath);
    var fullPath = p.canonicalize(combined);
    if (!fullPath.startsWith(this._rootPath)) {
      throw ArgumentError(
                "Invalid path: ${relativePath}. The resolved path escapes the root directory.",
                'relativePath');
    }
    return fullPath;
  }

  /// Resolves a relative directory path to a safe absolute path under the root
  /// directory. An empty String resolves to the root directory itself.
  String resolveSafeDirectoryPath(String relativeDirectory) {
    if ((relativeDirectory == null || relativeDirectory.isEmpty)) {
      return this._rootPath.trimRight(p.separator, '/');
    }
    return this.resolveSafePath(relativeDirectory);
  }
}
