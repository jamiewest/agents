import 'package:extensions/system.dart';
import '../agent_skill.dart';
import '../agent_skill_resource.dart';
import '../agent_skill_script.dart';
import 'agent_inline_skill_content_builder.dart';
import 'agent_inline_skill_resource.dart';
import 'agent_inline_skill_script.dart';
import '../../../../json_stubs.dart';

/// Abstract base class for defining skills as C# classes that bundle all
/// components together.
///
/// Remarks: Inherit from this class to create a self-contained skill
/// definition. Override the abstract properties to provide name, description,
/// and instructions. Scripts and resources can be defined in two ways:
/// Attribute-based (recommended): Annotate methods with
/// [AgentSkillScriptAttribute] to define scripts, and properties or methods
/// with [AgentSkillResourceAttribute] to define resources. These are
/// automatically discovered via reflection on `TSelf`. This approach is
/// compatible with Native AOT. Explicit override: Override [Resources] and
/// [Scripts], using [String)], [JsonSerializerOptions)], and
/// [JsonSerializerOptions)] to define inline resources and scripts. This
/// approach is also compatible with Native AOT. Multi-level inheritance
/// limitation: Discovery reflects only on `TSelf`, so if a further-derived
/// subclass adds new attributed members, they will not be discovered unless
/// that subclass also uses the CRTP pattern (e.g., `class SpecialSkill :
/// AgentClassSkill&lt;SpecialSkill&gt;`).
///
/// [TSelf] The concrete skill type. This type parameter is annotated with
/// [DynamicallyAccessedMembersAttribute] to ensure that the IL trimmer and
/// Native AOT compiler preserve the members needed for attribute-based
/// discovery.
abstract class AgentClassSkill<TSelf> extends AgentSkill {
  AgentClassSkill();

  String? _content;

  bool _resourcesDiscovered;

  bool _scriptsDiscovered;

  List<AgentSkillResource>? _reflectedResources;

  List<AgentSkillScript>? _reflectedScripts;

  /// Gets the raw instructions text for this skill.
  final String instructions;

  /// Returns resources discovered via reflection by scanning for members
  /// annotated with . This discovery is compatible with Native AOT because is
  /// annotated with . The result is cached after the first access.
  ///
  /// Remarks: Returns resources discovered via reflection by scanning `TSelf`
  /// for members annotated with [AgentSkillResourceAttribute]. This discovery
  /// is compatible with Native AOT because `TSelf` is annotated with
  /// [DynamicallyAccessedMembersAttribute]. The result is cached after the
  /// first access.
  final List<AgentSkillResource>? resources;

  /// Returns scripts discovered via reflection by scanning for methods
  /// annotated with . This discovery is compatible with Native AOT because is
  /// annotated with . The result is cached after the first access.
  ///
  /// Remarks: Returns scripts discovered via reflection by scanning `TSelf` for
  /// methods annotated with [AgentSkillScriptAttribute]. This discovery is
  /// compatible with Native AOT because `TSelf` is annotated with
  /// [DynamicallyAccessedMembersAttribute]. The result is cached after the
  /// first access.
  final List<AgentSkillScript>? scripts;

  /// Gets the [JsonSerializerOptions] used to marshal parameters and return
  /// values for scripts and resources.
  ///
  /// Remarks: Override this property to provide custom serialization options.
  /// This value is used by reflection-discovered scripts and resources, and
  /// also as a fallback by [JsonSerializerOptions)] and
  /// [JsonSerializerOptions)] when no explicit [JsonSerializerOptions] is
  /// passed to those methods. The default value is `null`, which causes
  /// [DefaultOptions] to be used.
  JsonSerializerOptions? get serializerOptions {
    return null;
  }

  /// Returns a synthesized XML document containing name, description,
  /// instructions, resources, and scripts. The result is cached after the first
  /// access. Override to provide custom content.
  ///
  /// Remarks: Returns a synthesized XML document containing name, description,
  /// instructions, resources, and scripts. The result is cached after the first
  /// access. Override to provide custom content.
  String get content {
    return this._content ??= AgentInlineSkillContentBuilder.build(
        this.frontmatter.name,
        this.frontmatter.description,
        this.instructions,
        this.resources,
        this.scripts);
  }

  /// Creates a skill resource backed by a static value.
  ///
  /// Returns: A new [AgentSkillResource] instance.
  ///
  /// [name] The resource name.
  ///
  /// [value] The static resource value.
  ///
  /// [description] An optional description of the resource.
  AgentSkillResource createResource(
    String name,
    String? description,
    {Object? value, Delegate? method, JsonSerializerOptions? serializerOptions, },
  ) {
    return agentInlineSkillResource(name, value, description);
  }

  /// Creates a skill script backed by a delegate.
  ///
  /// Returns: A new [AgentSkillScript] instance.
  ///
  /// [name] The script name.
  ///
  /// [method] A method to execute when the script is invoked.
  ///
  /// [description] An optional description of the script.
  ///
  /// [serializerOptions] Optional [JsonSerializerOptions] used to marshal the
  /// delegate's parameters and return value. When `null`, falls back to
  /// [SerializerOptions].
  AgentSkillScript createScript(
    String name,
    Delegate method,
    {String? description, JsonSerializerOptions? serializerOptions, },
  ) {
    return agentInlineSkillScript(
      name,
      method,
      description,
      serializerOptions ?? this.serializerOptions,
    );
  }

  List<AgentSkillResource>? discoverResources() {
    var resources = null;
    var selfType = TSelf;
    for (final property in selfType.getProperties(DiscoveryBindingFlags)) {
      var attr = property.getCustomAttribute<AgentSkillResourceAttribute>();
      if (attr == null) {
        continue;
      }
      var getter = property.getGetMethod(nonPublic: true);
      if (getter == null) {
        continue;
      }
      if (getter.getParameters().length > 0) {
        throw StateError(
                    "Property ${property.name} on type "${selfType.name}' is an indexer and cannot be used as a skill resource. ' +
                    "Remove the [AgentSkillResource] attribute or use a non-indexer property.");
      }
      var name = attr.name ?? property.name;
      if (resources?.exists((r) => r.name == name) == true) {
        throw StateError("Skill ${this.frontmatter.name} already has a resource named "${name}'. Ensure each [AgentSkillResource] has a unique name.');
      }
      resources ??= [];
      resources.add(agentInlineSkillResource(
                name: name,
                method: getter,
                target: getter.isStatic ? null : this,
                description: property.getCustomAttribute<DescriptionAttribute>()?.description,
                serializerOptions: this.serializerOptions));
    }
    for (final method in selfType.getMethods(DiscoveryBindingFlags)) {
      var attr = method.getCustomAttribute<AgentSkillResourceAttribute>();
      if (attr == null) {
        continue;
      }
      validateResourceMethodParameters(method, selfType);
      var name = attr.name ?? method.name;
      if (resources?.exists((r) => r.name == name) == true) {
        throw StateError("Skill ${this.frontmatter.name} already has a resource named "${name}'. Ensure each [AgentSkillResource] has a unique name.');
      }
      resources ??= [];
      resources.add(agentInlineSkillResource(
                name: name,
                method: method,
                target: method.isStatic ? null : this,
                description: method.getCustomAttribute<DescriptionAttribute>()?.description,
                serializerOptions: this.serializerOptions));
    }
    return resources;
  }

  static void validateResourceMethodParameters(MethodInfo method, Type skillType, ) {
    for (final param in method.getParameters()) {
      if (param.parameterType != IServiceProvider &&
                param.parameterType != CancellationToken) {
        throw StateError(
                    "Method ${method.name} on type "${skillType.name}" has parameter ${param.name} of type " +
                    "${param.parameterType} which cannot be supplied when reading a resource. " +
                    "Resource methods may only accept IServiceProvider and/or CancellationToken parameters. " +
                    "Remove the [AgentSkillResource] attribute or change the method signature.");
      }
    }
  }

  List<AgentSkillScript>? discoverScripts() {
    var scripts = null;
    for (final method in TSelf.getMethods(DiscoveryBindingFlags)) {
      var attr = method.getCustomAttribute<AgentSkillScriptAttribute>();
      if (attr == null) {
        continue;
      }
      var name = attr.name ?? method.name;
      if (scripts?.exists((s) => s.name == name) == true) {
        throw StateError("Skill ${this.frontmatter.name} already has a script named "${name}'. Ensure each [AgentSkillScript] has a unique name.');
      }
      scripts ??= [];
      scripts.add(agentInlineSkillScript(
                name: name,
                method: method,
                target: method.isStatic ? null : this,
                description: method.getCustomAttribute<DescriptionAttribute>()?.description,
                serializerOptions: this.serializerOptions));
    }
    return scripts;
  }
}
