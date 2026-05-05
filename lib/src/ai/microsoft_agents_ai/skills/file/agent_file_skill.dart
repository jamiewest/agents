import '../agent_skill.dart';
import '../agent_skill_frontmatter.dart';
import '../agent_skill_resource.dart';
import '../agent_skill_script.dart';

/// An [AgentSkill] discovered from a filesystem directory backed by a
/// SKILL.md file.
class AgentFileSkill extends AgentSkill {
  /// Initializes a new instance of the [AgentFileSkill] class.
  ///
  /// [frontmatter] The parsed frontmatter metadata for this skill.
  ///
  /// [content] The full raw SKILL.md file content including YAML frontmatter.
  ///
  /// [path] Absolute path to the directory containing this skill.
  ///
  /// [resources] Resources discovered for this skill.
  ///
  /// [scripts] Scripts discovered for this skill.
  AgentFileSkill(
    AgentSkillFrontmatter frontmatter,
    String content,
    String path, {
    List<AgentSkillResource>? resources = null,
    List<AgentSkillScript>? scripts = null,
  }) : frontmatter = frontmatter,
       content = content,
       path = path {
    this._originalContent = content;
    this._resources = resources ?? [];
    this._scripts = scripts ?? [];
  }

  late final List<AgentSkillResource> _resources;

  late final List<AgentSkillScript> _scripts;

  late final String _originalContent;

  String? _content;

  final AgentSkillFrontmatter frontmatter;

  /// Returns the raw SKILL.md content. When the skill has scripts, a
  /// &lt;scripts&gt;&lt;script
  /// name="..."&gt;&lt;parameters_schema&gt;...&lt;/parameters_schema&gt;&lt;/script&gt;&lt;/scripts&gt;
  /// block is appended with a per-script entry describing the expected argument
  /// format. The result is cached after the first access.
  ///
  /// Remarks: Returns the raw SKILL.md content. When the skill has scripts, a
  /// `&lt;scripts&gt;&lt;script
  /// name="..."&gt;&lt;parameters_schema&gt;...&lt;/parameters_schema&gt;&lt;/script&gt;&lt;/scripts&gt;`
  /// block is appended with a per-script entry describing the expected argument
  /// format. The result is cached after the first access.
  final String content;

  /// Gets the directory path where the skill was discovered.
  final String path;

  List<AgentSkillResource> get resources {
    return this._resources;
  }

  List<AgentSkillScript> get scripts {
    return this._scripts;
  }
}
