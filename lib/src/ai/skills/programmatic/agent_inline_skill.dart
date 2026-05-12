import 'package:extensions/ai.dart';

import '../../../json_stubs.dart';
import '../agent_skill.dart';
import '../agent_skill_frontmatter.dart';
import '../agent_skill_resource.dart';
import '../agent_skill_script.dart';
import 'agent_inline_skill_content_builder.dart';
import 'agent_inline_skill_resource.dart';
import 'agent_inline_skill_script.dart';

/// A skill defined entirely in code with resources and scripts.
class AgentInlineSkill extends AgentSkill {
  AgentInlineSkill(
    String instructions, {
    JsonSerializerOptions? serializerOptions,
    AgentSkillFrontmatter? frontmatter,
    String? name,
    String? description,
    String? license,
    String? compatibility,
    String? allowedTools,
    AdditionalPropertiesDictionary? metadata,
  }) : _instructions = instructions,
       _serializerOptions = serializerOptions,
       frontmatter =
           frontmatter ??
           AgentSkillFrontmatter(
             name ?? '',
             description ?? '',
             license: license,
             compatibility: compatibility,
             allowedTools: allowedTools,
             metadata: metadata,
           );

  final String _instructions;
  final JsonSerializerOptions? _serializerOptions;
  final List<AgentInlineSkillResource> _resources = [];
  final List<AgentInlineSkillScript> _scripts = [];
  String? _cachedContent;

  @override
  final AgentSkillFrontmatter frontmatter;

  @override
  String get content => _cachedContent ??= AgentInlineSkillContentBuilder.build(
    frontmatter.name,
    frontmatter.description,
    _instructions,
    _resources,
    _scripts,
  );

  @override
  List<AgentSkillResource>? get resources =>
      _resources.isEmpty ? null : List<AgentSkillResource>.of(_resources);

  @override
  List<AgentSkillScript>? get scripts =>
      _scripts.isEmpty ? null : List<AgentSkillScript>.of(_scripts);

  AgentInlineSkill addResource(
    String name,
    String? description, {
    Object? value,
    Function? method,
    JsonSerializerOptions? serializerOptions,
  }) {
    _resources.add(
      AgentInlineSkillResource(
        name,
        description,
        value: value,
        method: method,
        serializerOptions: serializerOptions ?? _serializerOptions,
      ),
    );
    _cachedContent = null;
    return this;
  }

  AgentInlineSkill addScript(
    String name,
    Function method, {
    String? description,
    JsonSerializerOptions? serializerOptions,
  }) {
    _scripts.add(
      AgentInlineSkillScript(
        name,
        description,
        serializerOptions ?? _serializerOptions,
        method: method,
      ),
    );
    _cachedContent = null;
    return this;
  }
}
