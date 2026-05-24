import '../agent_skill.dart';
import '../agent_skill_frontmatter.dart';
import '../agent_skill_resource.dart';
import '../agent_skill_script.dart';

/// An [AgentSkill] discovered from a filesystem directory backed by a
/// SKILL.md file.
class AgentFileSkill extends AgentSkill {
  /// Creates an [AgentFileSkill] with [frontmatter], raw content, [path], and
  /// optional [resources] and [scripts].
  AgentFileSkill(
    this.frontmatter,
    this._originalContent,
    this.path, {
    List<AgentSkillResource>? resources,
    List<AgentSkillScript>? scripts,
  }) : _resources = resources ?? [],
       _scripts = scripts ?? [];

  final List<AgentSkillResource> _resources;
  final List<AgentSkillScript> _scripts;
  final String _originalContent;
  String? _content;

  @override
  final AgentSkillFrontmatter frontmatter;

  /// Returns the raw SKILL.md content.
  ///
  /// When the skill has scripts, a `<scripts>` block is appended with a
  /// per-script entry describing the expected argument format. The result is
  /// cached after the first access.
  @override
  String get content => _content ??= _scripts.isEmpty
      ? _originalContent
      : '$_originalContent\n${_buildScriptsBlock()}';

  /// Gets the directory path where the skill was discovered.
  final String path;

  @override
  List<AgentSkillResource> get resources {
    return _resources;
  }

  @override
  List<AgentSkillScript> get scripts {
    return _scripts;
  }

  String _buildScriptsBlock() {
    final buffer = StringBuffer('\n<scripts>\n');
    for (final script in _scripts) {
      final schema = script.parametersSchema;
      if (schema == null) {
        buffer.writeln('  <script name="${script.name}"/>');
      } else {
        buffer.writeln('  <script name="${script.name}">');
        buffer.writeln('    <parameters_schema>$schema</parameters_schema>');
        buffer.writeln('  </script>');
      }
    }
    buffer.write('</scripts>');
    return buffer.toString();
  }
}
