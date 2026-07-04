import '../../../func_typedefs.dart';
import 'agent_file_skill_filter_context.dart';

/// Configuration options for file-based skill sources.
///
/// Use this class to configure file-based skill discovery without relying on
/// positional constructor or method parameters. New options can be added here
/// without breaking existing callers.
class AgentFileSkillsSourceOptions {
  AgentFileSkillsSourceOptions();

  /// Allowed file extensions for skill resources. When `null`, defaults to
  /// `.md`, `.json`, `.yaml`, `.yml`, `.csv`, `.xml`, `.txt`.
  Iterable<String>? allowedResourceExtensions;

  /// Allowed file extensions for skill scripts. When `null`, defaults to
  /// `.py`, `.js`, `.sh`, `.ps1`, `.cs`, `.csx`.
  Iterable<String>? allowedScriptExtensions;

  /// Relative directory paths to scan for script files within each skill
  /// directory.
  ///
  /// Values may be single-segment names (e.g., `"scripts"`) or multi-segment
  /// relative paths (e.g., `"sub/scripts"`). Use `"."` to include files
  /// directly at the skill root. Leading `"./"` prefixes, trailing separators,
  /// and backslashes are normalized automatically; paths containing `".."`
  /// segments or absolute paths are rejected. When `null`, defaults to
  /// `scripts`. When set, replaces the defaults entirely.
  Iterable<String>? scriptDirectories;

  /// Relative directory paths to scan for resource files within each skill
  /// directory.
  ///
  /// Values may be single-segment names (e.g., `"references"`) or
  /// multi-segment relative paths (e.g., `"sub/resources"`). Use `"."` to
  /// include files directly at the skill root. Leading `"./"` prefixes,
  /// trailing separators, and backslashes are normalized automatically; paths
  /// containing `".."` segments or absolute paths are rejected. When `null`,
  /// defaults to `references` and `assets`. When set, replaces the defaults
  /// entirely.
  Iterable<String>? resourceDirectories;

  /// Maximum depth to scan for resource files within each resource directory.
  ///
  /// A value of `1` scans only the resource directory itself. A value of `2`
  /// scans the resource directory and its immediate child directories. When
  /// `null`, defaults to `1`, preserving the historical behavior.
  int? resourceSearchDepth;

  /// Filters discovered script files.
  ///
  /// The predicate receives an [AgentFileSkillFilterContext] containing the
  /// skill's name and the file's path relative to the skill directory. Return
  /// `true` to include the file or `false` to exclude it. When `null`, all
  /// scripts matching the allowed extensions are included.
  Func<AgentFileSkillFilterContext, bool>? scriptFilter;

  /// Filters discovered resource files.
  ///
  /// The predicate receives an [AgentFileSkillFilterContext] containing the
  /// skill's name and the file's path relative to the skill directory. Return
  /// `true` to include the file or `false` to exclude it. When `null`, all
  /// resources matching the allowed extensions are included.
  Func<AgentFileSkillFilterContext, bool>? resourceFilter;
}
