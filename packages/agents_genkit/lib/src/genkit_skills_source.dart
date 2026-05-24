import 'package:agents/agents.dart';
import 'package:extensions/system.dart';
import 'package:genkit/genkit.dart';

/// An [AgentSkillsSource] that exposes Genkit [Tool]s as [AgentSkill]s.
///
/// Each tool's name and description become the skill's frontmatter; a short
/// markdown document is synthesised as the skill content so the agent
/// understands when and how to invoke each tool.
///
/// Combine with other sources via [AggregatingAgentSkillsSource]:
/// ```dart
/// AggregatingAgentSkillsSource([
///   AgentFileSkillsSource(directory: skillsDir),
///   GenkitSkillsSource(tools: [myTool, anotherTool]),
/// ]);
/// ```
class GenkitSkillsSource extends AgentSkillsSource {
  /// Creates a [GenkitSkillsSource] from an explicit list of [Tool]s.
  GenkitSkillsSource({required List<Tool<dynamic, dynamic>> tools})
      : _tools = List.unmodifiable(tools);

  final List<Tool<dynamic, dynamic>> _tools;

  @override
  Future<List<AgentSkill>> getSkills({
    CancellationToken? cancellationToken,
  }) async =>
      _tools.map(_toSkill).toList();

  AgentSkill _toSkill(Tool<dynamic, dynamic> tool) {
    final kebabName = _toKebabCase(tool.name);
    final description = tool.description ?? tool.name;
    final inputInfo = tool.inputSchema?.jsonSchema != null
        ? '\n\n**Input schema:** `${tool.inputSchema!.jsonSchema}`'
        : '';
    final instructions = '$description$inputInfo';
    return AgentInlineSkill(
      instructions,
      name: kebabName,
      description: description,
    );
  }

  /// Converts [name] to a valid [AgentSkillFrontmatter] kebab-case name.
  ///
  /// Rules: lowercase, replace non-alphanumeric runs with a single hyphen,
  /// trim leading/trailing hyphens, truncate to 64 characters.
  static String _toKebabCase(String name) {
    var result = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (result.isEmpty) result = 'tool';
    if (result.length > AgentSkillFrontmatter.maxNameLength) {
      result = result.substring(0, AgentSkillFrontmatter.maxNameLength);
      result = result.replaceAll(RegExp(r'-+$'), '');
    }
    return result;
  }
}
