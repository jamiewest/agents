/// Provides contextual information about a discovered file to the
/// [AgentFileSkillsSourceOptions.scriptFilter] and
/// [AgentFileSkillsSourceOptions.resourceFilter] predicates.
class AgentFileSkillFilterContext {
  /// Creates a filter context for the file at [relativeFilePath] belonging to
  /// the skill named [skillName].
  AgentFileSkillFilterContext(this.skillName, this.relativeFilePath);

  /// The name of the skill as declared in the SKILL.md frontmatter.
  final String skillName;

  /// The path to the script or resource file relative to the skill directory,
  /// using forward slashes. For root-level files this is just the filename; for
  /// nested files it includes the subdirectory.
  final String relativeFilePath;
}
