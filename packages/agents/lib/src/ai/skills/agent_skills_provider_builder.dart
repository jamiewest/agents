import 'package:extensions/logging.dart';

import '../../func_typedefs.dart';
import 'agent_in_memory_skills_source.dart';
import 'agent_skill.dart';
import 'agent_skills_provider.dart';
import 'agent_skills_provider_options.dart';
import 'agent_skills_source.dart';
import 'agent_skills_source_context.dart';
import 'aggregating_agent_skills_source.dart';
import 'decorators/caching_agent_skills_source.dart';
import 'decorators/caching_agent_skills_source_options.dart';
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
  Func2<AgentSkill, AgentSkillsSourceContext, bool>? _filter;
  bool _disableCaching = false;
  CachingAgentSkillsSourceOptions? _cachingOptions;

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

  /// Adds a custom skill source.
  ///
  /// The provider returned by [build] takes ownership of [source] and
  /// disposes it when the provider is disposed. Because the same instance is
  /// reused on every [build] call, do not build more than one provider from a
  /// builder that captures a shared [source]; otherwise disposing one
  /// provider would dispose the source out from under the others. To build
  /// multiple providers, use [useSourceFactory], which creates a fresh source
  /// per build, or pass the source directly to an [AgentSkillsProvider]
  /// constructor with `ownsSource: false` to retain ownership.
  AgentSkillsProviderBuilder useSource(AgentSkillsSource source) {
    _sourceFactories.add((_, _) => source);
    return this;
  }

  /// Adds a custom skill source created by a factory that receives the
  /// builder's logger factory at build time. Use this when the source needs
  /// logging and should not require the caller to pass a [LoggerFactory]
  /// explicitly.
  AgentSkillsProviderBuilder useSourceFactory(
    AgentSkillsSource Function(LoggerFactory? loggerFactory) factory,
  ) {
    _sourceFactories.add((_, loggerFactory) => factory(loggerFactory));
    return this;
  }

  AgentSkillsProviderBuilder usePromptTemplate(String promptTemplate) {
    getOrCreateOptions().skillsInstructionPrompt = promptTemplate;
    return this;
  }

  /// Disables caching of the resolved skill list. By default, skills are
  /// fetched once and cached; calling this method causes the source pipeline
  /// to be invoked on every request.
  AgentSkillsProviderBuilder disableCaching() {
    _disableCaching = true;
    return this;
  }

  /// Configures skill caching behavior.
  AgentSkillsProviderBuilder useCachingOptions(
    void Function(CachingAgentSkillsSourceOptions options) configure,
  ) {
    configure(_cachingOptions ??= CachingAgentSkillsSourceOptions());
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

  AgentSkillsProviderBuilder useFilter(
    Func2<AgentSkill, AgentSkillsSourceContext, bool> predicate,
  ) {
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

    if (!_disableCaching) {
      source = CachingAgentSkillsSource(source, options: _cachingOptions);
    }

    // Apply user-specified filter, then dedup.
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
      ownsSource: true,
      options: _options,
      loggerFactory: _loggerFactory,
    );
  }

  AgentSkillsProviderOptions getOrCreateOptions() {
    return _options ??= AgentSkillsProviderOptions();
  }
}
