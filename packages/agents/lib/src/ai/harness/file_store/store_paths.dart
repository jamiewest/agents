import 'agent_file_store.dart';

/// Internal helper for normalizing and validating relative store paths and
/// matching glob patterns. Shared across [AgentFileStore] implementations.
class StorePaths {
  StorePaths._();

  /// Normalizes a relative path by replacing backslashes with forward slashes,
  /// trimming leading and trailing separators, and collapsing consecutive
  /// separators. Also validates that the path does not contain rooted paths,
  /// drive roots, or `.`/`..` traversal segments.
  static String normalizeRelativePath(String path, {bool isDirectory = false}) {
    if (path.trim().isEmpty) {
      if (!isDirectory) {
        throw ArgumentError(
          'A file path must not be empty or whitespace-only.',
          'path',
        );
      }

      return '';
    }

    final normalized = path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+|/+$'), '');

    if (path.startsWith('/') ||
        path.startsWith('\\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      throw ArgumentError(
        "Invalid path: '$path'. Paths must be relative and must not start with '/', '\\', or a drive root.",
        'path',
      );
    }

    final cleanSegments = <String>[];
    for (final segment in normalized.split('/')) {
      if (segment.isEmpty) {
        continue;
      }

      if (segment == '.' || segment == '..') {
        throw ArgumentError(
          "Invalid path: '$path'. Paths must not contain '.' or '..' segments.",
          'path',
        );
      }

      cleanSegments.add(segment);
    }

    final result = cleanSegments.join('/');
    if (!isDirectory && result.isEmpty) {
      throw ArgumentError('A file path must not be empty.', 'path');
    }

    return result;
  }

  /// Creates a [StorePathGlobMatcher] for the specified glob pattern.
  static StorePathGlobMatcher createGlobMatcher(String filePattern) {
    return StorePathGlobMatcher(filePattern);
  }

  /// Determines whether a file name matches a pre-built glob matcher.
  static bool matchesGlob(String fileName, StorePathGlobMatcher? matcher) {
    if (matcher == null) {
      return true;
    }

    return matcher.matches(fileName);
  }
}

/// Minimal case-insensitive glob matcher for file names.
class StorePathGlobMatcher {
  StorePathGlobMatcher(String pattern)
    : _regex = RegExp('^${_globToRegex(pattern)}\$', caseSensitive: false);

  final RegExp _regex;

  bool matches(String fileName) {
    return _regex.hasMatch(fileName);
  }

  static String _globToRegex(String pattern) {
    final buffer = StringBuffer();
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      switch (char) {
        case '*':
          buffer.write('.*');
        case '?':
          buffer.write('.');
        default:
          buffer.write(RegExp.escape(char));
      }
    }
    return buffer.toString();
  }
}
