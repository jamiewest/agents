import '../agent_skill.dart';
import '../agent_skill_resource.dart';
import '../agent_skill_script.dart';
import 'agent_inline_skill_content_builder.dart';
import 'agent_inline_skill_resource.dart';
import 'agent_inline_skill_script.dart';
import '../../../json_stubs.dart';

/// Abstract base class for defining skills as Dart classes that bundle all
/// components together.
///
/// Inherit from this class to create a self-contained skill definition.
/// Override [name], [description], and [instructions], then override
/// [resources] and [scripts] (or use [createResource]/[createScript]) to
/// define the skill's capabilities.
abstract class AgentClassSkill<TSelf> extends AgentSkill {
  AgentClassSkill();

  String? _content;

  /// Gets the raw instructions text for this skill.
  String get instructions;

  /// Returns resources for this skill. Override to provide explicit resources,
  /// or rely on [discoverResources] for reflection-based discovery.
  @override
  List<AgentSkillResource>? get resources => null;

  /// Returns scripts for this skill. Override to provide explicit scripts,
  /// or rely on [discoverScripts] for reflection-based discovery.
  @override
  List<AgentSkillScript>? get scripts => null;

  /// Gets the [JsonSerializerOptions] used to marshal parameters and return
  /// values for scripts and resources.
  JsonSerializerOptions? get serializerOptions => null;

  /// Returns a synthesized XML document containing name, description,
  /// instructions, resources, and scripts. Cached after first access.
  @override
  String get content {
    return _content ??= AgentInlineSkillContentBuilder.build(
      frontmatter.name,
      frontmatter.description,
      instructions,
      resources,
      scripts,
    );
  }

  /// Creates a skill resource backed by a static value.
  AgentSkillResource createResource(
    String name,
    String? description, {
    Object? value,
    Function? method,
    JsonSerializerOptions? serializerOptions,
  }) {
    return AgentInlineSkillResource(name, description, value: value);
  }

  /// Creates a skill script backed by a function.
  AgentSkillScript createScript(
    String name,
    Function method, {
    String? description,
    JsonSerializerOptions? serializerOptions,
  }) {
    return AgentInlineSkillScript(
      name,
      description,
      serializerOptions ?? this.serializerOptions,
      method: method,
    );
  }

  /// Reflection-based resource discovery is not supported in Dart.
  /// Override [resources] instead.
  List<AgentSkillResource>? discoverResources() => null;

  /// Reflection-based script discovery is not supported in Dart.
  /// Override [scripts] instead.
  List<AgentSkillScript>? discoverScripts() => null;
}
