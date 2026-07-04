import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../../abstractions/ai_context.dart';
import '../../abstractions/ai_context_provider.dart';
import '../../json_stubs.dart';
import 'agent_in_memory_skills_source.dart';
import 'agent_skill.dart';
import 'agent_skill_script.dart';
import 'agent_skills_provider_options.dart';
import 'agent_skills_source.dart';
import 'agent_skills_source_context.dart';
import 'decorators/caching_agent_skills_source.dart';
import 'decorators/deduplicating_agent_skills_source.dart';
import 'file/agent_file_skill_script_runner.dart';
import 'file/agent_file_skills_source.dart';
import 'file/agent_file_skills_source_options.dart';
import 'package:agents/src/abstractions/invoking_context.dart';

/// An [AIContextProvider] that exposes agent skills from one or more
/// [AgentSkillsSource] instances.
///
/// This provider implements the progressive disclosure pattern from the
/// [Agent Skills specification](https://agentskills.io/): skill names and
/// descriptions are advertised in the system prompt, the full skill body is
/// returned via the `load_skill` tool, supplementary content is read on
/// demand via `read_skill_resource`, and scripts are executed via
/// `run_skill_script`.
///
/// The provider can optionally own the lifetime of its underlying
/// [AgentSkillsSource]. When constructed via the convenience parameters
/// (skill paths or in-memory skills) or via `AgentSkillsProviderBuilder`,
/// the source pipeline is created internally and owned by the provider, so
/// disposing the provider disposes the pipeline. When constructed from a
/// caller-supplied [AgentSkillsSource], ownership is controlled by the
/// `ownsSource` parameter and defaults to the caller retaining ownership.
class AgentSkillsProvider extends AIContextProvider implements Disposable {
  AgentSkillsProvider({
    String? skillPath,
    Iterable<String>? skillPaths,
    AgentFileSkillScriptRunner? scriptRunner,
    AgentFileSkillsSourceOptions? fileOptions,
    Iterable<AgentSkill>? skills,
    AgentSkillsSource? source,
    bool ownsSource = false,
    AgentSkillsProviderOptions? options,
    LoggerFactory? loggerFactory,
  }) : _source = _resolveSource(
         skillPath: skillPath,
         skillPaths: skillPaths,
         scriptRunner: scriptRunner,
         fileOptions: fileOptions,
         skills: skills,
         source: source,
         loggerFactory: loggerFactory,
       ),
       _ownsSource = source == null || ownsSource,
       _options = options,
       _logger = (loggerFactory ?? NullLoggerFactory.instance).createLogger(
         'AgentSkillsProvider',
       ) {
    final prompt = options?.skillsInstructionPrompt;
    if (prompt != null) {
      validatePromptTemplate(prompt, 'options');
    }
  }

  /// The name of the tool that loads a skill.
  static const String loadSkillToolName = 'load_skill';

  /// The name of the tool that reads a skill resource.
  static const String readSkillResourceToolName = 'read_skill_resource';

  /// The name of the tool that runs a skill script.
  static const String runSkillScriptToolName = 'run_skill_script';

  /// The names of the tools that only read (never execute scripts from) the
  /// skills source.
  static const Set<String> _readOnlyToolNames = {
    loadSkillToolName,
    readSkillResourceToolName,
  };

  /// The names of all tools exposed by this provider.
  static const Set<String> _allToolNames = {
    loadSkillToolName,
    readSkillResourceToolName,
    runSkillScriptToolName,
  };

  /// An auto-approval rule that approves the read-only skill tools
  /// ([loadSkillToolName] and [readSkillResourceToolName]).
  ///
  /// This rule only applies when approval is enabled for the matching tools
  /// in [AgentSkillsProviderOptions]. Add it to
  /// `ToolApprovalAgentOptions.autoApprovalRules` to automatically approve
  /// only the tools that read skill content, while still prompting for script
  /// execution ([runSkillScriptToolName]) if it also requires approval.
  static Future<bool> Function(FunctionCallContent functionCall)
  get readOnlyToolsAutoApprovalRule => _readOnlyToolsAutoApprovalRule;

  /// An auto-approval rule that approves all skill tools, including the
  /// script execution tool ([runSkillScriptToolName]).
  static Future<bool> Function(FunctionCallContent functionCall)
  get allToolsAutoApprovalRule => _allToolsAutoApprovalRule;

  static Future<bool> _readOnlyToolsAutoApprovalRule(
    FunctionCallContent functionCall,
  ) async => _readOnlyToolNames.contains(functionCall.name);

  static Future<bool> _allToolsAutoApprovalRule(
    FunctionCallContent functionCall,
  ) async => _allToolNames.contains(functionCall.name);

  /// Placeholder token for the generated skills list in the prompt template.
  static const String skillsPlaceholder = '{skills}';

  /// The default system prompt template used to advertise skills.
  static const String defaultSkillsInstructionPrompt = '''
You have access to skills containing domain-specific knowledge and capabilities.
Each skill provides specialized instructions, reference documents, and assets for specific tasks.

<available_skills>
{skills}
</available_skills>

When a task aligns with a skill's domain, follow these steps in exact order:
- Use `load_skill` to retrieve the skill's instructions.
- Follow the provided guidance.
- Use `read_skill_resource` to read any referenced resources, using the name exactly as listed
   (e.g. `"style-guide"` not `"style-guide.md"`, `"references/FAQ.md"` not `"FAQ.md"`).
- Use `run_skill_script` to run referenced scripts, using the name exactly as listed.
Only load what is needed, when it is needed.''';

  final AgentSkillsSource _source;
  final bool _ownsSource;
  final AgentSkillsProviderOptions? _options;
  final Logger _logger;
  bool _disposed = false;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final skills = await _source.getSkills(
      AgentSkillsSourceContext(context.agent, context.session),
      cancellationToken: cancellationToken,
    );
    if (skills.isEmpty) {
      return super.provideAIContext(
        context,
        cancellationToken: cancellationToken,
      );
    }

    return AIContext()
      ..instructions = buildSkillsInstructions(skills)
      ..tools = buildTools(skills);
  }

  /// Releases the resources used by this provider. When the provider owns
  /// its underlying [AgentSkillsSource] (see the `ownsSource` constructor
  /// parameter), the source is disposed as well.
  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_ownsSource) {
      _source.dispose();
    }
  }

  List<AIFunction> buildTools(List<AgentSkill> skills) {
    return [
      _wrapWithApprovalIfRequired(
        AIFunctionFactory.create(
          name: loadSkillToolName,
          description: 'Loads the full content of a specific skill',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'skillName': {'type': 'string'},
            },
            'required': ['skillName'],
          },
          callback: (arguments, {cancellationToken}) => loadSkill(
            skills,
            _stringArgument(arguments, 'skillName'),
            cancellationToken: cancellationToken,
          ),
        ),
        _options?.disableLoadSkillApproval != true,
      ),
      _wrapWithApprovalIfRequired(
        AIFunctionFactory.create(
          name: readSkillResourceToolName,
          description:
              'Reads a resource associated with a skill, such as references, assets, or dynamic data.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'skillName': {'type': 'string'},
              'resourceName': {'type': 'string'},
            },
            'required': ['skillName', 'resourceName'],
          },
          callback: (arguments, {cancellationToken}) => readSkillResource(
            skills,
            _stringArgument(arguments, 'skillName'),
            _stringArgument(arguments, 'resourceName'),
            arguments.services as ServiceProvider?,
            cancellationToken: cancellationToken,
          ),
        ),
        _options?.disableReadSkillResourceApproval != true,
      ),
      _wrapWithApprovalIfRequired(
        AIFunctionFactory.create(
          name: runSkillScriptToolName,
          description: 'Runs a script associated with a skill.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'skillName': {'type': 'string'},
              'scriptName': {'type': 'string'},
              'arguments': {},
            },
            'required': ['skillName', 'scriptName'],
          },
          callback: (arguments, {cancellationToken}) => runSkillScript(
            skills,
            _stringArgument(arguments, 'skillName'),
            _stringArgument(arguments, 'scriptName'),
            arguments: JsonElement(arguments['arguments']),
            serviceProvider: arguments.services as ServiceProvider?,
            cancellationToken: cancellationToken,
          ),
        ),
        _options?.disableRunSkillScriptApproval != true,
      ),
    ];
  }

  static AIFunction _wrapWithApprovalIfRequired(
    AIFunction function,
    bool requireApproval,
  ) => requireApproval ? ApprovalRequiredAIFunction(function) : function;

  String buildSkillsInstructions(List<AgentSkill> skills) {
    final promptTemplate =
        _options?.skillsInstructionPrompt ?? defaultSkillsInstructionPrompt;
    final sorted = List<AgentSkill>.of(skills)
      ..sort(
        (left, right) =>
            left.frontmatter.name.compareTo(right.frontmatter.name),
      );
    final buffer = StringBuffer();
    for (final skill in sorted) {
      buffer
        ..writeln('  <skill>')
        ..writeln('    <name>${escapeXml(skill.frontmatter.name)}</name>')
        ..writeln(
          '    <description>${escapeXml(skill.frontmatter.description)}</description>',
        )
        ..writeln('  </skill>');
    }

    return promptTemplate.replaceAll(
      skillsPlaceholder,
      buffer.toString().trimRight(),
    );
  }

  Future<String> loadSkill(
    List<AgentSkill> skills,
    String skillName, {
    CancellationToken? cancellationToken,
  }) async {
    if (skillName.trim().isEmpty) {
      return 'Error: Skill name cannot be empty.';
    }
    final skill = _findSkill(skills, skillName);
    if (skill == null) {
      return "Error: Skill '$skillName' not found.";
    }
    logSkillLoading(_logger, skillName);
    return skill.getContent(cancellationToken: cancellationToken);
  }

  Future<Object?> readSkillResource(
    List<AgentSkill> skills,
    String skillName,
    String resourceName,
    ServiceProvider? serviceProvider, {
    CancellationToken? cancellationToken,
  }) async {
    if (skillName.trim().isEmpty) {
      return 'Error: Skill name cannot be empty.';
    }
    if (resourceName.trim().isEmpty) {
      return 'Error: Resource name cannot be empty.';
    }
    final skill = _findSkill(skills, skillName);
    if (skill == null) {
      return "Error: Skill '$skillName' not found.";
    }
    try {
      final resource = await skill.getResource(
        resourceName,
        cancellationToken: cancellationToken,
      );
      if (resource == null) {
        return "Error: Resource '$resourceName' not found in skill "
            "'$skillName'.";
      }
      return await resource.read(
        serviceProvider: serviceProvider,
        cancellationToken: cancellationToken,
      );
    } catch (error) {
      logResourceReadError(_logger, skillName, resourceName, error);
      rethrow;
    }
  }

  Future<Object?> runSkillScript(
    List<AgentSkill> skills,
    String skillName,
    String scriptName, {
    JsonElement? arguments,
    ServiceProvider? serviceProvider,
    CancellationToken? cancellationToken,
  }) async {
    if (skillName.trim().isEmpty) {
      return 'Error: Skill name cannot be empty.';
    }
    if (scriptName.trim().isEmpty) {
      return 'Error: Script name cannot be empty.';
    }
    final skill = _findSkill(skills, skillName);
    if (skill == null) {
      return "Error: Skill '$skillName' not found.";
    }
    try {
      final script = _findByName(skill.scripts, scriptName);
      if (script == null) {
        return "Error: Script '$scriptName' not found in skill '$skillName'.";
      }
      return await script.run(
        skill,
        arguments,
        serviceProvider,
        cancellationToken: cancellationToken,
      );
    } catch (error) {
      logScriptExecutionError(_logger, skillName, scriptName, error);
      if (_options?.includeDetailedErrors == true) {
        return "Error: Failed to execute script '$scriptName' from skill "
            "'$skillName'. Exception: $error";
      }
      rethrow;
    }
  }

  /// Validates that a custom prompt template contains the required
  /// placeholder tokens.
  static void validatePromptTemplate(String template, String paramName) {
    if (!template.contains(skillsPlaceholder)) {
      throw ArgumentError.value(
        template,
        paramName,
        "The custom prompt template must contain the '$skillsPlaceholder' "
        'placeholder for the generated skills list.',
      );
    }
  }

  static void logSkillLoading(Logger logger, String skillName) {
    if (logger.isEnabled(LogLevel.information)) {
      logger.logInformation('Loading skill: $skillName');
    }
  }

  static void logResourceReadError(
    Logger logger,
    String skillName,
    String resourceName,
    Object error,
  ) {
    if (logger.isEnabled(LogLevel.error)) {
      logger.logError(
        "Failed to read resource '$resourceName' from skill '$skillName'",
        error: error,
      );
    }
  }

  static void logScriptExecutionError(
    Logger logger,
    String skillName,
    String scriptName,
    Object error,
  ) {
    if (logger.isEnabled(LogLevel.error)) {
      logger.logError(
        "Failed to execute script '$scriptName' from skill '$skillName'",
        error: error,
      );
    }
  }

  static String escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static AgentSkill? _findSkill(List<AgentSkill> skills, String skillName) {
    for (final skill in skills) {
      if (skill.frontmatter.name == skillName) {
        return skill;
      }
    }
    return null;
  }

  static T? _findByName<T extends Object>(Iterable<T>? items, String name) {
    if (items == null) {
      return null;
    }
    for (final item in items) {
      final itemName = switch (item) {
        AgentSkillScript(:final name) => name,
        dynamic value => value.name as String?,
      };
      if (itemName == name) {
        return item;
      }
    }
    return null;
  }

  static String _stringArgument(AIFunctionArguments arguments, String name) {
    return (arguments[name] ?? '').toString();
  }

  static AgentSkillsSource _resolveSource({
    String? skillPath,
    Iterable<String>? skillPaths,
    AgentFileSkillScriptRunner? scriptRunner,
    AgentFileSkillsSourceOptions? fileOptions,
    Iterable<AgentSkill>? skills,
    AgentSkillsSource? source,
    LoggerFactory? loggerFactory,
  }) {
    if (source != null) {
      return source;
    }
    if (skills != null) {
      return DeduplicatingAgentSkillsSource(
        CachingAgentSkillsSource(AgentInMemorySkillsSource(skills)),
        loggerFactory: loggerFactory,
      );
    }
    final paths = [?skillPath, ...?skillPaths];
    if (paths.isNotEmpty) {
      return DeduplicatingAgentSkillsSource(
        CachingAgentSkillsSource(
          AgentFileSkillsSource(
            paths,
            scriptRunner: scriptRunner,
            options: fileOptions,
            loggerFactory: loggerFactory,
          ),
        ),
        loggerFactory: loggerFactory,
      );
    }
    return AgentInMemorySkillsSource(const []);
  }
}
