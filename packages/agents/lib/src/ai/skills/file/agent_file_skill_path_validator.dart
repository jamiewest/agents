import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import 'agent_file_skill_path_scope.dart';

/// Validates paths used by file-backed skills.
class AgentFileSkillPathValidator {
  AgentFileSkillPathValidator._();

  /// Revalidates a discovered file against its trusted path [scope]
  /// immediately before use, returning the resolved path.
  ///
  /// Discovery-time validation alone is not enough: the file, the skill
  /// directory, or any directory between it and the configured root can be
  /// replaced with a link after the skill is discovered and before it is read
  /// or run. [fileKind] and [fileName] name the offending entry in the
  /// resulting error.
  ///
  /// Following the boundary check this package already uses elsewhere (see
  /// PORTING.md), containment is enforced by canonicalizing the path — which
  /// resolves any link in it — and requiring the result to stay under
  /// [AgentFileSkillPathScope.skillDirectoryPrefix]. A skill directory swapped
  /// for a link therefore resolves outside the recorded prefix and is
  /// rejected, without walking the path segment by segment.
  ///
  /// Throws a [StateError] when the path escapes the skill directory or
  /// resolves through a link, and a [FileSystemException] when the file no
  /// longer exists.
  static String validateForUse(
    String fullPath,
    AgentFileSkillPathScope scope,
    String fileKind,
    String fileName, {
    FileSystem fs = const LocalFileSystem(),
  }) {
    final resolvedFilePath = p.canonicalize(fullPath);

    if (!resolvedFilePath.startsWith(scope.skillDirectoryPrefix)) {
      throw StateError(
        "$fileKind file '$fileName' references a path outside the skill "
        'directory.',
      );
    }

    if (!fs.file(resolvedFilePath).existsSync()) {
      throw FileSystemException(
        "$fileKind file '$fileName' was not found in the skill directory.",
        resolvedFilePath,
      );
    }

    if (isLinkOrInaccessible(resolvedFilePath, fs: fs)) {
      throw StateError(
        "$fileKind file '$fileName' has a symbolic link in its path; links "
        'are not allowed.',
      );
    }

    return resolvedFilePath;
  }

  /// Whether the entity at [path] is a symbolic link, or cannot be inspected
  /// at all — both are treated as unsafe.
  static bool isLinkOrInaccessible(
    String path, {
    FileSystem fs = const LocalFileSystem(),
  }) {
    try {
      return fs.typeSync(path, followLinks: false) == FileSystemEntityType.link;
    } on FileSystemException {
      return true;
    }
  }
}
