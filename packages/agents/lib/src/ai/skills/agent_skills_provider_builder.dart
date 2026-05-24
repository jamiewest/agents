import 'package:extensions/logging.dart';

import '../../func_typedefs.dart';
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

/// Fluent builder for constructing an [AgentSkillsProvider] backed by a
/// composite source.
class AgentSkillsProviderBuilder {
  AgentSkillsProviderBuilder();

  final List<
    AgentSkillsSource Function(
      AgentFileSkillScriptRunner? scriptRunner,
      LoggerFactory? loggerFactory,
    )
  >
  _sourceFactories = [];

  AgentSkillsProviderOptions? _options;
  LoggerFactory? _loggerFactory;
  AgentFileSkillScriptRunner? _scriptRunner;
  Func<AgentSkill, bool>? _filter;

  AgentSkillsProviderBuilder useFileSkill(
    String skillPath, {
    AgentFileSkillsSourceOptions? options,
    AgentFileSkillScriptRunner? scriptRunner,
  }) {
    return useFileSkills(
      [skillPath],
      options: options,
      scriptRunner: scriptRunner,
    );
  }

  AgentSkillsProviderBuilder useFileSkills(
    Iterable<String> skillPaths, {
    AgentFileSkillsSourceOptions? options,
    AgentFileSkillScriptRunner? scriptRunner,
  }) {
    final paths = List<String>.of(skillPaths);
    _sourceFactories.add((builderScriptRunner, loggerFactory) {
      final resolvedRunner = scriptRunner ?? builderScriptRunner;
      return AgentFileSkillsSource(
        paths,
        scriptRunner: resolvedRunner,
        options: options,
        loggerFactory: loggerFactory,
      );
    });
    return this;
  }

  AgentSkillsProviderBuilder useSkill(AgentSkill skill) => useSkills([skill]);

  AgentSkillsProviderBuilder useSkills(Iterable<AgentSkill> skills) {
    final source = AgentInMemorySkillsSource(skills);
    _sourceFactories.add((_, _) => source);
    return this;
  }

  AgentSkillsProviderBuilder useSource(AgentSkillsSource source) {
    _sourceFactories.add((_, _) => source);
    return this;
  }

  AgentSkillsProviderBuilder usePromptTemplate(String promptTemplate) {
    getOrCreateOptions().skillsInstructionPrompt = promptTemplate;
    return this;
  }

  AgentSkillsProviderBuilder useScriptApproval({bool enabled = true}) {
    getOrCreateOptions().scriptApproval = enabled;
    return this;
  }

  AgentSkillsProviderBuilder useFileScriptRunner(
    AgentFileSkillScriptRunner runner,
  ) {
    _scriptRunner = runner;
    return this;
  }

  AgentSkillsProviderBuilder useLoggerFactory(LoggerFactory loggerFactory) {
    _loggerFactory = loggerFactory;
    return this;
  }

  AgentSkillsProviderBuilder useFilter(Func<AgentSkill, bool> predicate) {
    _filter = predicate;
    return this;
  }

  AgentSkillsProviderBuilder useOptions(
    void Function(AgentSkillsProviderOptions options) configure,
  ) {
    configure(getOrCreateOptions());
    return this;
  }

  AgentSkillsProvider build() {
    final resolvedSources = _sourceFactories
        .map((factory) => factory(_scriptRunner, _loggerFactory))
        .toList();

    AgentSkillsSource source;
    if (resolvedSources.isEmpty) {
      source = AgentInMemorySkillsSource(const []);
    } else if (resolvedSources.length == 1) {
      source = resolvedSources.single;
    } else {
      source = AggregatingAgentSkillsSource(resolvedSources);
    }

    final filter = _filter;
    if (filter != null) {
      source = FilteringAgentSkillsSource(
        source,
        filter,
        loggerFactory: _loggerFactory,
      );
    }

    source = DeduplicatingAgentSkillsSource(
      source,
      loggerFactory: _loggerFactory,
    );

    return AgentSkillsProvider(
      source: source,
      options: _options,
      loggerFactory: _loggerFactory,
    );
  }

  AgentSkillsProviderOptions getOrCreateOptions() {
    return _options ??= AgentSkillsProviderOptions();
  }
}
