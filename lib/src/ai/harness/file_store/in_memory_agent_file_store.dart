import 'dart:math';

import 'package:extensions/system.dart';

import 'agent_file_store.dart';
import 'file_search_match.dart';
import 'file_search_result.dart';
import 'store_paths.dart';

/// An in-memory implementation of [AgentFileStore] that stores files in a
/// dictionary.
///
/// Remarks: This implementation is suitable for testing and lightweight
/// scenarios where persistence is not required. Directory concepts are
/// simulated using path prefixes; no explicit directory structure is
/// maintained.
class InMemoryAgentFileStore extends AgentFileStore {
  InMemoryAgentFileStore();

  final Map<String, _MemoryFile> _files = {};

  @override
  Future<void> writeFileAsync(
    String path,
    String content, [
    CancellationToken? cancellationToken,
  ]) async {
    final normalizedPath = StorePaths.normalizeRelativePath(path);
    _files[_key(normalizedPath)] = _MemoryFile(normalizedPath, content);
  }

  @override
  Future<String?> readFileAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async {
    final normalizedPath = StorePaths.normalizeRelativePath(path);
    return _files[_key(normalizedPath)]?.content;
  }

  @override
  Future<bool> deleteFileAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async {
    final normalizedPath = StorePaths.normalizeRelativePath(path);
    return _files.remove(_key(normalizedPath)) != null;
  }

  @override
  Future<List<String>> listFilesAsync(
    String directory, [
    CancellationToken? cancellationToken,
  ]) async {
    var prefix = StorePaths.normalizeRelativePath(directory, isDirectory: true);
    if (prefix.isNotEmpty && !prefix.endsWith('/')) {
      prefix += '/';
    }
    final prefixKey = _key(prefix);

    return _files.values
        .where((f) => _key(f.path).startsWith(prefixKey))
        .map((f) => f.path.substring(prefix.length))
        .where((name) => !name.contains('/'))
        .toList();
  }

  @override
  Future<bool> fileExistsAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async {
    final normalizedPath = StorePaths.normalizeRelativePath(path);
    return _files.containsKey(_key(normalizedPath));
  }

  @override
  Future<List<FileSearchResult>> searchFilesAsync(
    String directory,
    String regexPattern, [
    String? filePattern,
    CancellationToken? cancellationToken,
  ]) async {
    var prefix = StorePaths.normalizeRelativePath(directory, isDirectory: true);
    if (prefix.isNotEmpty && !prefix.endsWith('/')) {
      prefix += '/';
    }
    final prefixKey = _key(prefix);
    final regex = RegExp(regexPattern, caseSensitive: false);
    final matcher = filePattern != null
        ? StorePaths.createGlobMatcher(filePattern)
        : null;
    final results = <FileSearchResult>[];

    for (final file in _files.values) {
      if (!_key(file.path).startsWith(prefixKey)) {
        continue;
      }

      final relativeName = file.path.substring(prefix.length);
      if (relativeName.contains('/')) {
        continue;
      }

      if (!StorePaths.matchesGlob(relativeName, matcher)) {
        continue;
      }

      final result = _searchFile(relativeName, file.content, regex);
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
    StorePaths.normalizeRelativePath(path, isDirectory: true);
  }

  static String _key(String path) => path.toLowerCase();

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

class _MemoryFile {
  _MemoryFile(this.path, this.content);

  final String path;
  final String content;
}
