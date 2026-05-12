import 'dart:io';
import 'dart:math';

import 'package:extensions/system.dart';
import 'package:path/path.dart' as p;

import 'agent_file_store.dart';
import 'file_search_match.dart';
import 'file_search_result.dart';
import 'store_paths.dart';

/// A file-system-backed implementation of [AgentFileStore] that stores files
/// on disk under a configurable root directory.
///
/// All paths are resolved relative to the root directory provided at
/// construction time. Lexical path traversal attempts (for example, via `..`
/// segments or absolute paths) are rejected with an [ArgumentError]. The root
/// directory is created automatically if it does not already exist.
class FileSystemAgentFileStore extends AgentFileStore {
  /// Creates a [FileSystemAgentFileStore] for the given [rootDirectory].
  ///
  /// The directory is created if it does not already exist.
  FileSystemAgentFileStore(String? rootDirectory) {
    if (rootDirectory == null) {
      throw ArgumentError.notNull('rootDirectory');
    }
    if (rootDirectory.trim().isEmpty) {
      throw ArgumentError(
        'The root directory must not be empty or whitespace-only.',
        'rootDirectory',
      );
    }

    var fullRoot = p.normalize(p.absolute(rootDirectory));
    if (!fullRoot.endsWith(p.separator)) {
      fullRoot += p.separator;
    }

    _rootPath = fullRoot;
    Directory(fullRoot).createSync(recursive: true);
  }

  /// The canonical full path of the root directory, always ending with a
  /// directory separator.
  late final String _rootPath;

  @override
  Future<void> writeFileAsync(
    String path,
    String content, [
    CancellationToken? cancellationToken,
  ]) async {
    final fullPath = resolveSafePath(path);
    final parentDir = p.dirname(fullPath);
    Directory(parentDir).createSync(recursive: true);
    await File(fullPath).writeAsString(content);
  }

  @override
  Future<String?> readFileAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async {
    final fullPath = resolveSafePath(path);
    final file = File(fullPath);
    if (!file.existsSync()) {
      return null;
    }

    return file.readAsString();
  }

  @override
  Future<bool> deleteFileAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async {
    final fullPath = resolveSafePath(path);
    final file = File(fullPath);
    if (!file.existsSync()) {
      return false;
    }

    file.deleteSync();
    return true;
  }

  @override
  Future<List<String>> listFilesAsync(
    String directory, [
    CancellationToken? cancellationToken,
  ]) async {
    final fullDir = resolveSafeDirectoryPath(directory);
    final dir = Directory(fullDir);
    if (!dir.existsSync()) {
      return [];
    }

    return dir
        .listSync(followLinks: false)
        .whereType<File>()
        .map((file) => p.basename(file.path))
        .toList();
  }

  @override
  Future<bool> fileExistsAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async {
    final fullPath = resolveSafePath(path);
    return File(fullPath).existsSync();
  }

  @override
  Future<List<FileSearchResult>> searchFilesAsync(
    String directory,
    String regexPattern, [
    String? filePattern,
    CancellationToken? cancellationToken,
  ]) async {
    final fullDir = resolveSafeDirectoryPath(directory);
    final dir = Directory(fullDir);
    if (!dir.existsSync()) {
      return [];
    }

    final regex = RegExp(regexPattern, caseSensitive: false);
    final matcher = filePattern != null
        ? StorePaths.createGlobMatcher(filePattern)
        : null;
    final results = <FileSearchResult>[];

    for (final file in dir.listSync(followLinks: false).whereType<File>()) {
      final fileName = p.basename(file.path);
      if (!StorePaths.matchesGlob(fileName, matcher)) {
        continue;
      }

      final fileContent = await file.readAsString();
      final result = _searchFile(fileName, fileContent, regex);
      if (result != null) {
        results.add(result);
      }
    }

    return results;
  }

  @override
  Future<void> createDirectoryAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async {
    final fullPath = resolveSafeDirectoryPath(path);
    Directory(fullPath).createSync(recursive: true);
  }

  /// Resolves a relative file path to a safe absolute path under the root
  /// directory. Rejects paths that would escape the root via traversal or
  /// rooted paths.
  String resolveSafePath(String relativePath) {
    final normalized = StorePaths.normalizeRelativePath(relativePath);
    final nativePath = normalized.replaceAll('/', p.separator);
    final combined = p.join(_rootPath, nativePath);
    final fullPath = p.normalize(p.absolute(combined));

    if (!fullPath.startsWith(_rootPath)) {
      throw ArgumentError(
        "Invalid path: '$relativePath'. The resolved path escapes the root directory.",
        'relativePath',
      );
    }

    return fullPath;
  }

  /// Resolves a relative directory path to a safe absolute path under the root
  /// directory. An empty String resolves to the root directory itself.
  String resolveSafeDirectoryPath(String relativeDirectory) {
    if (relativeDirectory.isEmpty) {
      return _rootPath.replaceFirst(RegExp(r'[/\\]$'), '');
    }

    return resolveSafePath(relativeDirectory);
  }

  static FileSearchResult? _searchFile(
    String fileName,
    String fileContent,
    RegExp regex,
  ) {
    final lines = fileContent.split('\n');
    final matchingLines = <FileSearchMatch>[];
    String? firstSnippet;
    var lineStartOffset = 0;

    for (var i = 0; i < lines.length; i++) {
      final match = regex.firstMatch(lines[i]);
      if (match != null) {
        matchingLines.add(
          FileSearchMatch()
            ..lineNumber = i + 1
            ..line = lines[i].replaceFirst(RegExp(r'\r$'), ''),
        );

        if (firstSnippet == null) {
          final matchedValue = match.group(0) ?? '';
          final charIndex = lineStartOffset + match.start;
          final snippetStart = max(0, charIndex - 50);
          final snippetEnd = min(
            fileContent.length,
            charIndex + matchedValue.length + 50,
          );
          firstSnippet = fileContent.substring(snippetStart, snippetEnd);
        }
      }

      lineStartOffset += lines[i].length + 1;
    }

    if (matchingLines.isEmpty) {
      return null;
    }

    return FileSearchResult()
      ..fileName = fileName
      ..snippet = firstSnippet!
      ..matchingLines = matchingLines;
  }
}
