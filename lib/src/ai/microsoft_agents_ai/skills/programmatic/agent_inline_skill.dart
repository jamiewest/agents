import '../agent_skill.dart';
import '../agent_skill_frontmatter.dart';
import '../agent_skill_resource.dart';
import '../agent_skill_script.dart';
import '../agent_skills_provider.dart';
import '../agent_skills_provider_builder.dart';
import 'agent_inline_skill_content_builder.dart';
import 'agent_inline_skill_resource.dart';
import 'agent_inline_skill_script.dart';
import '../../../../json_stubs.dart';

/// A skill defined entirely in code with resources (static values or
/// delegates) and scripts (delegates).
///
/// Remarks: All calls to [String)], [JsonSerializerOptions)], and
/// [JsonSerializerOptions)] must be made before the skill's [Content] is
/// first accessed. Calls made after that point will not be reflected in the
/// generated [Content]. In typical usage, this means configuring all
/// resources and scripts before registering the skill with an
/// [AgentSkillsProvider] or [AgentSkillsProviderBuilder].
class AgentInlineSkill extends AgentSkill {
  /// Initializes a new instance of the [AgentInlineSkill] class with a
  /// pre-built [AgentSkillFrontmatter].
  ///
  /// [frontmatter] The skill frontmatter containing name, description, and
  /// other metadata.
  ///
  /// [instructions] Skill instructions text.
  ///
  /// [serializerOptions] Optional [JsonSerializerOptions] applied by default to
  /// all scripts and delegate resources added to this skill. Individual
  /// [JsonSerializerOptions)] and [JsonSerializerOptions)] calls can override
  /// this default. When `null`, [DefaultOptions] is used.
  AgentInlineSkill(
    String instructions,
    JsonSerializerOptions? serializerOptions, {
    AgentSkillFrontmatter? frontmatter = null,
    String? name = null,
    String? description = null,
    String? license = null,
    String? compatibility = null,
    String? allowedTools = null,
    AdditionalPropertiesDictionary? metadata = null,
  }) : _instructions = instructions,
       _serializerOptions = serializerOptions {
    this.frontmatter = frontmatter;
  }

  final String _instructions;

  final JsonSerializerOptions? _serializerOptions;

  List<AgentInlineSkillResource>? _resources;

  List<AgentInlineSkillScript>? _scripts;

  String? _cachedContent;

  late final AgentSkillFrontmatter frontmatter;

  String get content {
    return this._cachedContent ??= AgentInlineSkillContentBuilder.build(
      this.frontmatter.name,
      this.frontmatter.description,
      this._instructions,
      this._resources,
      this._scripts,
    );
  }

  List<AgentSkillResource>? get resources {
    return this._resources;
  }

  List<AgentSkillScript>? get scripts {
    return this._scripts;
  }

  /// Registers a static resource with this skill.
  ///
  /// Returns: This instance, for chaining.
  ///
  /// [name] The resource name.
  ///
  /// [value] The static resource value.
  ///
  /// [description] An optional description of the resource.
  AgentInlineSkill addResource(
    String name,
    String? description, {
    Object? value,
    Delegate? method,
    JsonSerializerOptions? serializerOptions,
  }) {
    (this._resources ??= []).add(
      agentInlineSkillResource(name, value, description),
    );
    return this;
  }

  /// Registers a script with this skill, backed by a C# delegate. The
  /// delegate's parameters and return type are automatically marshaled via
  /// `AIFunctionFactory`.
  ///
  /// Returns: This instance, for chaining.
  ///
  /// [name] The script name.
  ///
  /// [method] A method to execute when the script is invoked.
  ///
  /// [description] An optional description of the script.
  ///
  /// [serializerOptions] Optional [JsonSerializerOptions] for this script's
  /// delegate marshaling. When `null`, the skill-level default (if any) is
  /// used; otherwise [DefaultOptions] is used.
  AgentInlineSkill addScript(
    String name,
    Delegate method, {
    String? description,
    JsonSerializerOptions? serializerOptions,
  }) {
    (this._scripts ??= []).add(
      agentInlineSkillScript(
        name,
        method,
        description,
        serializerOptions ?? this._serializerOptions,
      ),
    );
    return this;
  }
}
