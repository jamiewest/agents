import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import 'agent_file_skill_path_scope.dart';

/// Validates paths used by file-backed skills.
abstract final class AgentFileSkillPathValidator {
  /// Revalidates a discovered file against its trusted path [scope]
  /// immediately before use, and returns the resolved path.
  ///
  /// Throws a [StateError] when the file escapes the skill directory or when
  /// a link appears anywhere below the configured discovery root, and a
  /// [FileSystemException] when the file no longer exists.
  static String validateForUse(
    String fullPath,
    AgentFileSkillPathScope scope,
    String fileKind,
    String fileName, {
    required FileSystem fs,
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

    // Scan from the configured discovery root rather than from the skill
    // directory, so that a skill directory — or any directory between it and
    // the root — that was replaced with a link after discovery is rejected as
    // well.
    if (hasLinkOrInaccessibleInPath(
      resolvedFilePath,
      scope.trustedRootPrefix,
      fs: fs,
    )) {
      throw StateError(
        "$fileKind file '$fileName' has a symbolic link in its path; links "
        'are not allowed.',
      );
    }

    return resolvedFilePath;
  }

  /// Whether any segment of [pathToCheck] below [trustedBasePath] is a link
  /// or cannot be inspected.
  static bool hasLinkOrInaccessibleInPath(
    String pathToCheck,
    String trustedBasePath, {
    required FileSystem fs,
  }) {
    if (!pathToCheck.startsWith(trustedBasePath)) {
      return true;
    }

    final relativePath = pathToCheck.substring(trustedBasePath.length);
    var currentPath = trustedBasePath;
    while (currentPath.length > 1 &&
        (currentPath.endsWith('/') || currentPath.endsWith(r'\'))) {
      currentPath = currentPath.substring(0, currentPath.length - 1);
    }

    for (final segment in p.split(relativePath)) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      currentPath = p.join(currentPath, segment);
      if (isLinkOrInaccessible(currentPath, fs: fs)) {
        return true;
      }
    }

    return false;
  }

  /// Whether the entity at [path] is a symbolic link, or cannot be inspected
  /// at all — both are treated as unsafe.
  static bool isLinkOrInaccessible(String path, {required FileSystem fs}) {
    try {
      return fs.typeSync(path, followLinks: false) == FileSystemEntityType.link;
    } on FileSystemException {
      return true;
    }
  }
}
