import 'package:path/path.dart' as p;
import '../file_memory/file_memory_provider.dart';
import 'agent_file_store.dart';

/// Internal helper for normalizing and validating relative store paths and
/// matching glob patterns. Shared across [AgentFileStore] implementations and
/// [FileMemoryProvider].
class StorePaths {
  StorePaths();

  /// Normalizes a relative path by replacing backslashes with forward slashes,
  /// trimming leading and trailing separators, and collapsing consecutive
  /// separators. Also validates that the path does not contain rooted paths,
  /// drive roots, or `.`/`..` traversal segments.
  ///
  /// Returns: The normalized forward-slash path.
  ///
  /// [path] The relative path to normalize.
  ///
  /// [isDirectory] When `true`, the path represents a directory and an empty
  /// result (meaning root) is allowed. When `false` (default), the path
  /// represents a file and an empty result is rejected.
  static String normalizeRelativePath(String path, {bool? isDirectory, }) {
    if ((path == null || path.trim().isEmpty)) {
      if (!isDirectory) {
        throw ArgumentError("A file path must not be empty or whitespace-only.", 'path');
      }
      return '';
    }
    var normalized = path.replaceAll('\\', '/').trim('/');
    if (p.isAbsolute(path) ||
            path.startsWith("/") ||
            path.startsWith("\\") ||
            (normalized.length >= 2 && char.isLetter(normalized[0]) && normalized[1] == ':')) {
      throw ArgumentError(
                "Invalid path: ${path}. Paths must be relative and must not start with "/', '\\', or a drive root.',
                'path');
    }
    var segments = normalized.split('/');
    var cleanSegments = List<String>(segments.length);
    for (final segment in segments) {
      if (segment.length == 0) {
        continue;
      }
      if (segment == "." || segment == "..") {
        throw ArgumentError(
                    "Invalid path: ${path}. Paths must not contain ".' or '..' segments.',
                    'path');
      }
      cleanSegments.add(segment);
    }
    var result = cleanSegments.join("/");
    if (!isDirectory && result.length == 0) {
      throw ArgumentError("A file path must not be empty.", 'path');
    }
    return result;
  }

  /// Creates a [Matcher] for the specified glob pattern. Use the returned
  /// instance to test multiple file names without allocating a new matcher for
  /// each one.
  ///
  /// Returns: A [Matcher] configured with the specified pattern.
  ///
  /// [filePattern] The glob pattern to match against (e.g., `"*.md"`,
  /// `"research*"`).
  static Matcher createGlobMatcher(String filePattern) {
    var matcher = matcher();
    matcher.addInclude(filePattern);
    return matcher;
  }

  /// Determines whether a file name matches a pre-built glob [Matcher].
  ///
  /// Returns: `true` if the file name matches the pattern or if the matcher is
  /// `null`; otherwise, `false`.
  ///
  /// [fileName] The file name to test (not a full path — just the name).
  ///
  /// [matcher] A pre-built [Matcher] to test against. When `null`, this method
  /// returns `true` for any file name.
  static bool matchesGlob(String fileName, Matcher? matcher, ) {
    if (matcher == null) {
      return true;
    }
    var result = matcher.match(fileName);
    return result.hasMatches;
  }
}
