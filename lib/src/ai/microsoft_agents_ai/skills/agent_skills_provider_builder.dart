import '../../../func_typedefs.dart';
import 'agent_in_memory_skills_source.dart';
import 'agent_skill.dart';
import 'agent_skills_provider.dart';
import 'agent_skills_provider_options.dart';
import 'agent_skills_source.dart';
import 'aggregating_agent_skills_source.dart';
import 'decorators/deduplicating_agent_skills_source.dart';
import 'decorators/filtering_agent_skills_source.dart';
import 'file/agent_file_skill_script_runner.dart';
import 'file/agent_file_skills_source.dart';
import 'file/agent_file_skills_source_options.dart';
import 'programmatic/agent_class_skill.dart';
import 'programmatic/agent_inline_skill.dart';

/// Fluent builder for constructing an [AgentSkillsProvider] backed by a
/// composite source. Intended for advanced scenarios where the simple
/// [AgentSkillsProvider] constructors are insufficient.
///
/// Remarks: For simple, single-source scenarios, prefer the
/// [AgentSkillsProvider] constructors directly (e.g., passing a skill
/// directory path or a set of skills). Use this builder when you need one or
/// more of the following advanced capabilities: Mixed skill types — combine
/// file-based, code-defined ([AgentInlineSkill]), and class-based
/// ([AgentClassSkill]) skills in a single provider. Multiple file script
/// runners — use different script runners for different file skill
/// directories via per-source `scriptRunner` parameters on
/// [AgentFileSkillScriptRunner)] / [AgentFileSkillScriptRunner)]. Skill
/// filtering — include or exclude skills using a predicate via [Boolean})].
/// Example — combining file-based and code-defined skills: var provider = new
/// AgentSkillsProviderBuilder() .UseFileSkills("/path/to/skills")
/// .UseSkills(myInlineSkill1, myInlineSkill2)
/// .UseFileScriptRunner(SubprocessScriptRunner.RunAsync) .Build();
class AgentSkillsProviderBuilder {
  AgentSkillsProviderBuilder();

  final List<Func2<AgentFileSkillScriptRunner?, LoggerFactory?, AgentSkillsSource>> _sourceFactories = [];

  AgentSkillsProviderOptions? _options;

  late LoggerFactory? _loggerFactory;

  late AgentFileSkillScriptRunner? _scriptRunner;

  late Func<AgentSkill, bool>? _filter;

  /// Adds a file-based skill source that discovers skills from a filesystem
  /// directory.
  ///
  /// Returns: This builder instance for chaining.
  ///
  /// [skillPath] Path to search for skills.
  ///
  /// [options] Optional options that control skill discovery behavior.
  ///
  /// [scriptRunner] Optional runner for file-based scripts. When provided,
  /// overrides the builder-level runner set via [AgentFileSkillScriptRunner)].
  AgentSkillsProviderBuilder useFileSkill(
    String skillPath,
    {AgentFileSkillsSourceOptions? options, AgentFileSkillScriptRunner? scriptRunner, }
  ) {
    return this.useFileSkills([skillPath], options, scriptRunner);
  }

  /// Adds a file-based skill source that discovers skills from multiple
  /// filesystem directories.
  ///
  /// Returns: This builder instance for chaining.
  ///
  /// [skillPaths] Paths to search for skills.
  ///
  /// [options] Optional options that control skill discovery behavior.
  ///
  /// [scriptRunner] Optional runner for file-based scripts. When provided,
  /// overrides the builder-level runner set via [AgentFileSkillScriptRunner)].
  AgentSkillsProviderBuilder useFileSkills(
    Iterable<String> skillPaths,
    {AgentFileSkillsSourceOptions? options, AgentFileSkillScriptRunner? scriptRunner, }
  ) {
    this._sourceFactories.add((builderScriptRunner, loggerFactory) {
        
            var resolvedRunner = scriptRunner
                ?? builderScriptRunner
                ?? throw StateError('File-based skill sources require a script runner. Call ${'useFileScriptRunner'} or pass a runner to ${'useFileSkill'}/${'useFileSkills'}.');
            return agentFileSkillsSource(skillPaths, resolvedRunner, options, loggerFactory);
        });
    return this;
  }

  /// Adds a single skill.
  ///
  /// Returns: This builder instance for chaining.
  ///
  /// [skill] The skill to add.
  AgentSkillsProviderBuilder useSkill(AgentSkill skill) {
    return this.useSkills(skill);
  }

  /// Adds one or more skills.
  ///
  /// Returns: This builder instance for chaining.
  ///
  /// [skills] The skills to add.
  AgentSkillsProviderBuilder useSkills({List<AgentSkill>? skills}) {
    var source = agentInMemorySkillsSource(skills);
    this._sourceFactories.add((_, _) => source);
    return this;
  }

  /// Adds a custom skill source.
  ///
  /// Returns: This builder instance for chaining.
  ///
  /// [source] The custom skill source.
  AgentSkillsProviderBuilder useSource(AgentSkillsSource source) {
    source;
    this._sourceFactories.add((_, _) => source);
    return this;
  }

  /// Sets a custom system prompt template.
  ///
  /// Returns: This builder instance for chaining.
  ///
  /// [promptTemplate] The prompt template with `{skills}` placeholder for the
  /// skills list, `{resource_instructions}` for optional resource instructions,
  /// and `{script_instructions}` for optional script instructions.
  AgentSkillsProviderBuilder usePromptTemplate(String promptTemplate) {
    this.getOrCreateOptions().skillsInstructionPrompt = promptTemplate;
    return this;
  }

  /// Enables or disables the script approval gate.
  ///
  /// Returns: This builder instance for chaining.
  ///
  /// [enabled] Whether script execution requires approval.
  AgentSkillsProviderBuilder useScriptApproval({bool? enabled}) {
    this.getOrCreateOptions().scriptApproval = enabled;
    return this;
  }

  /// Sets the runner for file-based skill scripts.
  ///
  /// Returns: This builder instance for chaining.
  ///
  /// [runner] The delegate that runs file-based scripts.
  AgentSkillsProviderBuilder useFileScriptRunner(AgentFileSkillScriptRunner runner) {
    this._scriptRunner = runner;
    return this;
  }

  /// Sets the logger factory.
  ///
  /// Returns: This builder instance for chaining.
  ///
  /// [loggerFactory] The logger factory.
  AgentSkillsProviderBuilder useLoggerFactory(LoggerFactory loggerFactory) {
    this._loggerFactory = loggerFactory;
    return this;
  }

  /// Sets a filter predicate that controls which skills are included.
  ///
  /// Remarks: Skills for which the predicate returns `true` are kept; others
  /// are excluded. Only one filter is supported; calling this method again
  /// replaces any previously set filter.
  ///
  /// Returns: This builder instance for chaining.
  ///
  /// [predicate] A predicate that determines which skills to include.
  AgentSkillsProviderBuilder useFilter(Func<AgentSkill, bool> predicate) {
    predicate;
    this._filter = predicate;
    return this;
  }

  /// Configures the [AgentSkillsProviderOptions] using the provided delegate.
  ///
  /// Returns: This builder instance for chaining.
  ///
  /// [configure] A delegate to configure the options.
  AgentSkillsProviderBuilder useOptions(Action<AgentSkillsProviderOptions> configure) {
    configure;
    configure(this.getOrCreateOptions());
    return this;
  }

  /// Builds the [AgentSkillsProvider].
  ///
  /// Returns: A configured [AgentSkillsProvider].
  AgentSkillsProvider build() {
    var resolvedSources = List<AgentSkillsSource>(this._sourceFactories.length);
    for (final factory in this._sourceFactories) {
      resolvedSources.add(factory(this._scriptRunner, this._loggerFactory));
    }
    AgentSkillsSource source;
    if (resolvedSources.length == 1) {
      source = resolvedSources[0];
    } else {
      source = aggregatingAgentSkillsSource(resolvedSources);
    }
    if (this._filter != null) {
      source = filteringAgentSkillsSource(source, this._filter, this._loggerFactory);
    }
    source = deduplicatingAgentSkillsSource(source, this._loggerFactory);
    return agentSkillsProvider(source, this._options, this._loggerFactory);
  }

  AgentSkillsProviderOptions getOrCreateOptions() {
    return this._options ??= agentSkillsProviderOptions();
  }
}
