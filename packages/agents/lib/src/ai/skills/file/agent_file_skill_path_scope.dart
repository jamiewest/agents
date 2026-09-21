import 'package:path/path.dart' as p;

/// The path trust boundary of a discovered file-backed skill: the
/// host-configured discovery root together with the skill directory that was
/// found at or beneath it.
///
/// The configured root is retained alongside the skill directory so that a
/// file can be revalidated immediately before use against every directory
/// from the root down to the file, rather than only the segments below the
/// skill directory. Without the root, a skill directory — or a directory
/// between it and the root — that was swapped for a link after discovery
/// would never be inspected.
///
/// The configured root itself is never inspected: the host chose it
/// explicitly, so it defines the trust boundary rather than sitting inside
/// it, and it is allowed to be a link.
class AgentFileSkillPathScope {
  /// Creates a scope for a skill directory discovered beneath a configured
  /// discovery root.
  ///
  /// Throws an [ArgumentError] when [skillDirectoryFullPath] does not reside
  /// at or beneath [trustedRootFullPath].
  factory AgentFileSkillPathScope(
    String trustedRootFullPath,
    String skillDirectoryFullPath,
  ) {
    final skillDirectoryPath = p.canonicalize(skillDirectoryFullPath);
    final skillDirectoryPrefix = _ensureTrailingSeparator(skillDirectoryPath);
    final trustedRootPrefix = _ensureTrailingSeparator(
      p.canonicalize(trustedRootFullPath),
    );

    if (!skillDirectoryPrefix.startsWith(trustedRootPrefix)) {
      throw ArgumentError.value(
        skillDirectoryFullPath,
        'skillDirectoryFullPath',
        'The skill directory must reside at or beneath the configured skill '
            'discovery root.',
      );
    }

    return AgentFileSkillPathScope._(
      skillDirectoryPath,
      skillDirectoryPrefix,
      trustedRootPrefix,
    );
  }

  const AgentFileSkillPathScope._(
    this.skillDirectoryPath,
    this.skillDirectoryPrefix,
    this.trustedRootPrefix,
  );

  /// The absolute path of the skill directory.
  final String skillDirectoryPath;

  /// The skill directory with a trailing separator, for path-containment
  /// checks and for computing paths relative to the skill directory.
  ///
  /// The trailing separator stops containment checks from false-matching
  /// sibling directories: `/skills/myskill` matches `/skills/myskill-evil/`,
  /// but `/skills/myskill/` does not.
  final String skillDirectoryPrefix;

  /// The configured discovery root with a trailing separator, used as the
  /// base for link scans so that every segment beneath it is inspected.
  final String trustedRootPrefix;

  static String _ensureTrailingSeparator(String fullPath) {
    var trimmed = fullPath;
    while (trimmed.length > 1 &&
        (trimmed.endsWith('/') || trimmed.endsWith(r'\'))) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.endsWith(p.separator) ? trimmed : '$trimmed${p.separator}';
  }
}
