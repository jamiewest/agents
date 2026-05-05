import 'dart:io';
import 'dart:math';
import 'package:extensions/system.dart';
import 'agent_file_store.dart';
import 'file_search_match.dart';
import 'file_search_result.dart';
import 'store_paths.dart';
import '../../../../map_extensions.dart';

/// An in-memory implementation of [AgentFileStore] that stores files in a
/// dictionary.
///
/// Remarks: This implementation is suitable for testing and lightweight
/// scenarios where persistence is not required. Directory concepts are
/// simulated using path prefixes — no explicit directory structure is
/// maintained.
class InMemoryAgentFileStore extends AgentFileStore {
  InMemoryAgentFileStore();

  final ConcurrentDictionary<String, String> _files = new();

  @override
  Future writeFile(String path, String content, {CancellationToken? cancellationToken, }) {
    path = StorePaths.normalizeRelativePath(path);
    this._files[path] = content;
    return Task.value(null);
  }

  @override
  Future<String?> readFile(String path, {CancellationToken? cancellationToken, }) {
    path = StorePaths.normalizeRelativePath(path);
    this._files.tryGetValue(path);
    return Future.value(content);
  }

  @override
  Future<bool> deleteFile(String path, {CancellationToken? cancellationToken, }) {
    path = StorePaths.normalizeRelativePath(path);
    return Future.value(this._files.tryRemoveKey(path));
  }

  @override
  Future<List<String>> listFiles(String directory, {CancellationToken? cancellationToken, }) {
    var prefix = StorePaths.normalizeRelativePath(directory, isDirectory: true);
    if (prefix.length > 0 && !prefix.endsWith("/")) {
      prefix += "/";
    }
    var files = this._files.keys
            .where((k) => k.startsWith(prefix))
            .map((k) => k.substring(prefix.length))
            .where((k) => k.indexOf("/") < 0)
            .toList();
    return Future.value<List<String>>(files);
  }

  @override
  Future<bool> fileExists(String path, {CancellationToken? cancellationToken, }) {
    path = StorePaths.normalizeRelativePath(path);
    return Future.value(this._files.containsKey(path));
  }

  @override
  Future<List<FileSearchResult>> searchFiles(
    String directory,
    String regexPattern,
    {String? filePattern, CancellationToken? cancellationToken, },
  ) {
    var prefix = StorePaths.normalizeRelativePath(directory, isDirectory: true);
    if (prefix.length > 0 && !prefix.endsWith("/")) {
      prefix += "/";
    }
    var regex = regex(regexPattern, TimeSpan.fromSeconds(5));
    var matcher = filePattern != null ? StorePaths.createGlobMatcher(filePattern) : null;
    var results = List<FileSearchResult>();
    for (final kvp in this._files) {
      if (!kvp.key.startsWith(prefix)) {
        continue;
      }
      var relativeName = kvp.key.substring(prefix.length);
      if (relativeName.indexOf("/") >= 0) {
        continue;
      }
      if (!StorePaths.matchesGlob(relativeName, matcher)) {
        continue;
      }
      var fileContent = kvp.value;
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
    return Future.value<List<FileSearchResult>>(results);
  }

  @override
  Future createDirectory(String path, {CancellationToken? cancellationToken, }) {
    return Task.value(null);
  }
}
