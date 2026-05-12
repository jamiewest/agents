import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import '../../../json_stubs.dart';
import 'agent_in_memory_skills_source.dart';
import 'agent_skill.dart';
import 'agent_skill_script.dart';
import 'agent_skills_provider_options.dart';
import 'agent_skills_source.dart';
import 'decorators/deduplicating_agent_skills_source.dart';
import 'file/agent_file_skill_script_runner.dart';
import 'file/agent_file_skills_source.dart';
import 'file/agent_file_skills_source_options.dart';

/// An [AIContextProvider] that exposes agent skills from one or more
/// [AgentSkillsSource] instances.
class AgentSkillsProvider extends AIContextProvider {
  AgentSkillsProvider({
    String? skillPath,
    Iterable<String>? skillPaths,
    AgentFileSkillScriptRunner? scriptRunner,
    AgentFileSkillsSourceOptions? fileOptions,
    Iterable<AgentSkill>? skills,
    AgentSkillsSource? source,
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
       _options = options,
       _logger = (loggerFactory ?? NullLoggerFactory.instance).createLogger(
         'AgentSkillsProvider',
       ) {
    final prompt = options?.skillsInstructionPrompt;
    if (prompt != null) {
      validatePromptTemplate(prompt, 'options');
    }
  }

  static const String skillsPlaceholder = '{skills}';
  static const String scriptInstructionsPlaceholder = '{script_instructions}';
  static const String resourceInstructionsPlaceholder =
      '{resource_instructions}';
  static const String defaultSkillsInstructionPrompt = '''
You have access to skills containing domain-specific knowledge and capabilities.
Each skill provides specialized instructions, reference documents, and assets for specific tasks.

<available_skills>
{skills}
</available_skills>

When a task aligns with a skill's domain, follow these steps in exact order:
- Use `load_skill` to retrieve the skill's instructions.
- Follow the provided guidance.
{resource_instructions}
{script_instructions}
Only load what is needed, when it is needed.''';

  final AgentSkillsSource _source;
  final AgentSkillsProviderOptions? _options;
  final Logger _logger;
  Future<AIContext>? _contextFuture;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) {
    if (_options?.disableCaching == true) {
      return createContext(context, cancellationToken);
    }
    return getOrCreateContext(context, cancellationToken);
  }

  Future<AIContext> createContext(
    InvokingContext context,
    CancellationToken? cancellationToken,
  ) async {
    final skills = await _source.getSkills(
      cancellationToken: cancellationToken,
    );
    if (skills.isEmpty) {
      return super.provideAIContext(
        context,
        cancellationToken: cancellationToken,
      );
    }

    final hasScripts = skills.any((skill) => skill.scripts?.isNotEmpty == true);
    final hasResources = skills.any(
      (skill) => skill.resources?.isNotEmpty == true,
    );

    return AIContext()
      ..instructions = buildSkillsInstructions(
        skills,
        includeScriptInstructions: hasScripts,
        includeResourceInstructions: hasResources,
      )
      ..tools = buildTools(skills, hasScripts, hasResources);
  }

  Future<AIContext> getOrCreateContext(
    InvokingContext context,
    CancellationToken? cancellationToken,
  ) {
    return _contextFuture ??= createContext(context, cancellationToken);
  }

  List<AIFunction> buildTools(
    List<AgentSkill> skills,
    bool hasScripts,
    bool hasResources,
  ) {
    final tools = <AIFunction>[
      AIFunctionFactory.create(
        name: 'load_skill',
        description: 'Loads the full content of a specific skill.',
        parametersSchema: const {
          'type': 'object',
          'properties': {
            'skillName': {'type': 'string'},
          },
          'required': ['skillName'],
        },
        callback: (arguments, {cancellationToken}) async =>
            loadSkill(skills, _stringArgument(arguments, 'skillName')),
      ),
    ];

    if (hasResources) {
      tools.add(
        AIFunctionFactory.create(
          name: 'read_skill_resource',
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
      );
    }

    if (hasScripts) {
      tools.add(
        AIFunctionFactory.create(
          name: 'run_skill_script',
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
      );
    }

    return tools;
  }

  String buildSkillsInstructions(
    List<AgentSkill> skills, {
    required bool includeScriptInstructions,
    required bool includeResourceInstructions,
  }) {
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

    final resourceInstruction = includeResourceInstructions
        ? '- Use `read_skill_resource` to read any referenced resources, using the name exactly as listed.'
        : '';
    final scriptInstruction = includeScriptInstructions
        ? '- Use `run_skill_script` to run referenced scripts, using the name exactly as listed.'
        : '';

    return promptTemplate
        .replaceAll(skillsPlaceholder, buffer.toString().trimRight())
        .replaceAll(resourceInstructionsPlaceholder, resourceInstruction)
        .replaceAll(scriptInstructionsPlaceholder, scriptInstruction);
  }

  String loadSkill(List<AgentSkill> skills, String skillName) {
    if (skillName.trim().isEmpty) {
      return 'Error: Skill name cannot be empty.';
    }
    final skill = _findSkill(skills, skillName);
    if (skill == null) {
      return 'Error: Skill $skillName not found.';
    }
    logSkillLoading(_logger, skillName);
    return skill.content;
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
      return 'Error: Skill $skillName not found.';
    }
    final resource = _findByName(skill.resources, resourceName);
    if (resource == null) {
      return 'Error: Resource $resourceName not found in skill "$skillName".';
    }
    try {
      return await resource.read(
        serviceProvider: serviceProvider,
        cancellationToken: cancellationToken,
      );
    } catch (error) {
      logResourceReadError(_logger, skillName, resourceName, error);
      return 'Error: Failed to read resource $resourceName from skill "$skillName".';
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
      return 'Error: Skill $skillName not found.';
    }
    final script = _findByName(skill.scripts, scriptName);
    if (script == null) {
      return 'Error: Script $scriptName not found in skill "$skillName".';
    }
    try {
      return await script.run(
        skill,
        arguments,
        serviceProvider,
        cancellationToken: cancellationToken,
      );
    } catch (error) {
      logScriptExecutionError(_logger, skillName, scriptName, error);
      return 'Error: Failed to execute script $scriptName from skill "$skillName".';
    }
  }

  static void validatePromptTemplate(String template, String paramName) {
    if (!template.contains(skillsPlaceholder)) {
      throw ArgumentError.value(
        template,
        paramName,
        'The custom prompt template must contain the $skillsPlaceholder placeholder.',
      );
    }
    if (!template.contains(resourceInstructionsPlaceholder)) {
      throw ArgumentError.value(
        template,
        paramName,
        'The custom prompt template must contain the $resourceInstructionsPlaceholder placeholder.',
      );
    }
    if (!template.contains(scriptInstructionsPlaceholder)) {
      throw ArgumentError.value(
        template,
        paramName,
        'The custom prompt template must contain the $scriptInstructionsPlaceholder placeholder.',
      );
    }
  }

  static void logSkillLoading(Logger logger, String skillName) {
    if (logger.isEnabled(LogLevel.debug)) {
      logger.logDebug('Loading skill $skillName.');
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
        'Failed to read resource $resourceName from skill $skillName.',
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
        'Failed to execute script $scriptName from skill $skillName.',
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
        AgentInMemorySkillsSource(skills),
        loggerFactory: loggerFactory,
      );
    }
    final paths = [?skillPath, ...?skillPaths];
    if (paths.isNotEmpty) {
      return DeduplicatingAgentSkillsSource(
        AgentFileSkillsSource(
          paths,
          scriptRunner: scriptRunner,
          options: fileOptions,
          loggerFactory: loggerFactory,
        ),
        loggerFactory: loggerFactory,
      );
    }
    return AgentInMemorySkillsSource(const []);
  }
}
