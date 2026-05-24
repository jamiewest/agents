import 'agent_skill_frontmatter.dart';
import 'agent_skill_resource.dart';
import 'agent_skill_script.dart';
import 'file/agent_file_skill.dart';
import 'programmatic/agent_inline_skill.dart';

/// Abstract base class for all agent skills.
///
/// A skill represents a domain-specific capability with instructions,
/// resources, and scripts. Concrete implementations include [AgentFileSkill]
/// (filesystem-backed) and [AgentInlineSkill] (code-defined). Skill metadata
/// follows the Agent Skills specification.
abstract class AgentSkill {
  AgentSkill();

  /// Gets the frontmatter metadata for this skill.
  ///
  /// Contains the L1 discovery metadata (name, description, license,
  /// compatibility, etc.) as defined by the Agent Skills specification.
  AgentSkillFrontmatter get frontmatter;

  /// Gets the full skill content.
  ///
  /// For file-based skills this is the raw SKILL.md file content, optionally
  /// augmented with a synthesized scripts block when scripts are present. For
  /// code-defined skills this is a synthesized XML document containing name,
  /// description, and body (instructions, resources, scripts).
  String get content;

  /// Gets the resources associated with this skill, or `null` if none.
  ///
  /// The default implementation returns `null`. Override this property in
  /// derived classes to provide skill-specific resources.
  List<AgentSkillResource>? get resources {
    return null;
  }

  /// Gets the scripts associated with this skill, or `null` if none.
  ///
  /// The default implementation returns `null`. Override this property in
  /// derived classes to provide skill-specific scripts.
  List<AgentSkillScript>? get scripts {
    return null;
  }
}
