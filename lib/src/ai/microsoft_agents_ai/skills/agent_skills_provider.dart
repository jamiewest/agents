import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/dependency_injection.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import 'agent_skill.dart';
import 'agent_skills_provider_options.dart';
import 'agent_skills_source.dart';
import 'file/agent_file_skill_script_runner.dart';
import 'file/agent_file_skills_source_options.dart';
import '../../../json_stubs.dart';

/// An [AIContextProvider] that exposes agent skills from one or more
/// [AgentSkillsSource] instances.
///
/// Remarks: This provider implements the progressive disclosure pattern from
/// the Agent Skills specification : Advertise — skill names and descriptions
/// are injected into the system prompt. Load — the full skill body is
/// returned via the `load_skill` tool. Read resources — supplementary content
/// is read on demand via the `read_skill_resource` tool. Run scripts —
/// scripts are executed via the `run_skill_script` tool (when scripts exist).
class AgentSkillsProvider extends AIContextProvider {
  /// Initializes a new instance of the [AgentSkillsProvider] class that
  /// discovers file-based skills from a single directory. Duplicate skill names
  /// are automatically deduplicated (first occurrence wins).
  ///
  /// [skillPath] Path to search for skills.
  ///
  /// [scriptRunner] Optional delegate that runs file-based scripts. Required
  /// only when skills contain scripts.
  ///
  /// [fileOptions] Optional options that control skill discovery behavior.
  ///
  /// [options] Optional provider configuration.
  ///
  /// [loggerFactory] Optional logger factory.
  AgentSkillsProvider({String? skillPath = null, AgentFileSkillScriptRunner? scriptRunner = null, AgentFileSkillsSourceOptions? fileOptions = null, AgentSkillsProviderOptions? options = null, LoggerFactory? loggerFactory = null, Iterable<String>? skillPaths = null, List<AgentSkill>? skills = null, AgentSkillsSource? source = null, });

  final AgentSkillsSource _source;

  final AgentSkillsProviderOptions? _options;

  final Logger<AgentSkillsProvider> _logger;

  Future<AIContext>? _contextFuture;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context,
    {CancellationToken? cancellationToken, }
  ) async {
    if (this._options?.disableCaching == true) {
      return await this.createContextAsync(context, cancellationToken);
    }
    return await this.getOrCreateContextAsync(context, cancellationToken);
  }

  Future<AIContext> createContext(
    InvokingContext context,
    CancellationToken cancellationToken,
  ) async {
    var skills = await this._source.getSkillsAsync(cancellationToken);
    if (skills == null || skills.isEmpty) {
      return await super.provideAIContextAsync(context, cancellationToken);
    }
    var hasScripts = skills.any((s) => s.scripts ?.isNotEmpty == true);
    var hasResources = skills.any((s) => s.resources ?.isNotEmpty == true);
    return AIContext();
  }

  Future<AIContext> getOrCreateContext(
    InvokingContext context,
    CancellationToken cancellationToken,
  ) async {
    var tcs = TaskCompletionSource<AIContext>(TaskCreationOptions.runContinuationsAsynchronously);
    if ((() { final _old = this._contextTask; if (_old == null) this._contextTask = tcs.task; return _old; })() is { } existing) {
      return await existing;
    }
    try {
      var result = await this.createContextAsync(context, cancellationToken);
      tcs.setResult(result);
      return result;
    } catch (e, s) {
      if (e is Exception) {
        final ex = e as Exception;
        {
          this._contextTask = null;
          tcs.trySetException(ex);
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  List<AIFunction> buildTools(List<AgentSkill> skills, bool hasScripts, bool hasResources, ) {
    var tools = [
            AIFunctionFactory.create(
                (String skillName) => this.loadSkill(skills, skillName),
                name: "load_skill",
                description: "Loads the full content of a specific skill"),
        ];
    if (hasResources) {
      tools.add(AIFunctionFactory.create(
                (
                  String skillName,
                  String resourceName,
                  IServiceProvider? serviceProvider,
                  CancellationToken cancellationToken = default,
                ) =>
                    this.readSkillResourceAsync(
                      skills,
                      skillName,
                      resourceName,
                      serviceProvider,
                      cancellationToken,
                    ),
                name: "read_skill_resource",
                description: "Reads a resource associated with a skill, such as references, assets, or dynamic data."));
    }
    if (!hasScripts) {
      return tools;
    }
    var scriptFunction = AIFunctionFactory.create(
            (
              String skillName,
              String scriptName,
              JsonElement? arguments = null,
              IServiceProvider? serviceProvider = null,
              CancellationToken cancellationToken = default,
            ) =>
                this.runSkillScriptAsync(
                  skills,
                  skillName,
                  scriptName,
                  arguments,
                  serviceProvider,
                  cancellationToken,
                ),
            name: "run_skill_script",
            description: "Runs a script associated with a skill.");
    if (this._options?.scriptApproval == true) {
      return [...tools, approvalRequiredAIFunction(scriptFunction)];
    }
    return [...tools, scriptFunction];
  }

  String? buildSkillsInstructions(
    List<AgentSkill> skills,
    bool includeScriptInstructions,
    bool includeResourceInstructions,
  ) {
    var promptTemplate = this._options?.skillsInstructionPrompt ?? DefaultSkillsInstructionPrompt;
    var sb = StringBuffer();
    for (final skill in skills.orderBy((s) => s.frontmatter.name, )) {
      sb.writeln("  <skill>");
      sb.writeln('    <name>${SecurityElement.escape(skill.frontmatter.name)}</name>');
      sb.writeln('    <description>${SecurityElement.escape(skill.frontmatter.description)}</description>');
      sb.writeln("  </skill>");
    }
    var resourceInstruction = includeResourceInstructions
            ? """
            - Use `read_skill_resource` to read any referenced resources, using the name exactly as listed
               (e.g. `"style-guide"` not `"style-guide.md"`, `"references/FAQ.md"` not `"FAQ.md"`).
            """
            : '';
    var scriptInstruction = includeScriptInstructions
            ? "- Use `run_skill_script` to run referenced scripts, using the name exactly as listed."
            : '';
    return stringBuilder(promptTemplate)
            .replaceAll(SkillsPlaceholder, sb.toString().trimRight())
            .replaceAll(ResourceInstructionsPlaceholder, resourceInstruction)
            .replaceAll(ScriptInstructionsPlaceholder, scriptInstruction)
            .toString();
  }

  String loadSkill(List<AgentSkill> skills, String skillName, ) {
    if ((skillName == null || skillName.trim().isEmpty)) {
      return "Error: Skill name cannot be empty.";
    }
    var skill = skills?.firstOrDefault((skill) => skill.frontmatter.name == skillName);
    if (skill == null) {
      return "Error: Skill ${skillName} not found.";
    }
    logSkillLoading(this._logger, skillName);
    return skill.content;
  }

  Future<Object?> readSkillResource(
    List<AgentSkill> skills,
    String skillName,
    String resourceName,
    ServiceProvider? serviceProvider,
    {CancellationToken? cancellationToken, }
  ) async {
    if ((skillName == null || skillName.trim().isEmpty)) {
      return "Error: Skill name cannot be empty.";
    }
    if ((resourceName == null || resourceName.trim().isEmpty)) {
      return "Error: Resource name cannot be empty.";
    }
    var skill = skills?.firstOrDefault((skill) => skill.frontmatter.name == skillName);
    if (skill == null) {
      return "Error: Skill ${skillName} not found.";
    }
    var resource = skill.resources?.firstOrDefault((resource) => resource.name == resourceName);
    if (resource == null) {
      return 'Error: Resource ${resourceName} not found in skill "${skillName}".';
    }
    try {
      return await resource.readAsync(serviceProvider, cancellationToken);
    } catch (e, s) {
      if (e is Exception) {
        final ex = e as Exception;
        {
          logResourceReadError(this._logger, skillName, resourceName, ex);
          return 'Error: Failed to read resource ${resourceName} from skill "${skillName}".';
        }
      } else {
        rethrow;
      }
    }
  }

  Future<Object?> runSkillScript(
    List<AgentSkill> skills,
    String skillName,
    String scriptName,
    {JsonElement? arguments, ServiceProvider? serviceProvider, CancellationToken? cancellationToken, }
  ) async {
    if ((skillName == null || skillName.trim().isEmpty)) {
      return "Error: Skill name cannot be empty.";
    }
    if ((scriptName == null || scriptName.trim().isEmpty)) {
      return "Error: Script name cannot be empty.";
    }
    var skill = skills?.firstOrDefault((skill) => skill.frontmatter.name == skillName);
    if (skill == null) {
      return "Error: Skill ${skillName} not found.";
    }
    var script = skill.scripts?.firstOrDefault((resource) => resource.name == scriptName);
    if (script == null) {
      return 'Error: Script ${scriptName} not found in skill "${skillName}".';
    }
    try {
      return await script.runAsync(
        skill,
        arguments,
        serviceProvider,
        cancellationToken,
      ) ;
    } catch (e, s) {
      if (e is Exception) {
        final ex = e as Exception;
        {
          logScriptExecutionError(this._logger, skillName, scriptName, ex);
          return 'Error: Failed to execute script ${scriptName} from skill "${skillName}".';
        }
      } else {
        rethrow;
      }
    }
  }

  /// Validates that a custom prompt template contains the required placeholder
  /// tokens.
  static void validatePromptTemplate(String template, String paramName, ) {
    if (template.indexOf(SkillsPlaceholder) < 0) {
      throw ArgumentError(
                "The custom prompt template must contain the ${SkillsPlaceholder} placeholder for the generated skills list.",
                paramName);
    }
    if (template.indexOf(ResourceInstructionsPlaceholder) < 0) {
      throw ArgumentError(
                "The custom prompt template must contain the ${ResourceInstructionsPlaceholder} placeholder for resource instructions.",
                paramName);
    }
    if (template.indexOf(ScriptInstructionsPlaceholder) < 0) {
      throw ArgumentError(
                "The custom prompt template must contain the ${ScriptInstructionsPlaceholder} placeholder for script instructions.",
                paramName);
    }
  }

  static void logSkillLoading(Logger logger, String skillName, ) {
    // TODO: implement LogSkillLoading
    // C#:
    throw UnimplementedError('LogSkillLoading not implemented');
  }

  static void logResourceReadError(
    Logger logger,
    String skillName,
    String resourceName,
    Exception exception,
  ) {
    // TODO: implement LogResourceReadError
    // C#:
    throw UnimplementedError('LogResourceReadError not implemented');
  }

  static void logScriptExecutionError(
    Logger logger,
    String skillName,
    String scriptName,
    Exception exception,
  ) {
    // TODO: implement LogScriptExecutionError
    // C#:
    throw UnimplementedError('LogScriptExecutionError not implemented');
  }
}
