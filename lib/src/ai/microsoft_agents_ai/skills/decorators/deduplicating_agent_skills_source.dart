import 'package:extensions/system.dart';
import 'package:extensions/logging.dart';
import '../agent_skill.dart';
import '../agent_skills_source.dart';
import 'delegating_agent_skills_source.dart';

/// A skill source decorator that removes duplicate skills by name, keeping
/// only the first occurrence.
class DeduplicatingAgentSkillsSource extends DelegatingAgentSkillsSource {
  /// Initializes a new instance of the [DeduplicatingAgentSkillsSource] class.
  ///
  /// [innerSource] The inner source to deduplicate.
  ///
  /// [loggerFactory] Optional logger factory.
  DeduplicatingAgentSkillsSource(
    AgentSkillsSource innerSource, {
    LoggerFactory? loggerFactory = null,
  }) : super(innerSource) {
    this._logger = (loggerFactory ?? NullLoggerFactory.instance)
        .createLogger<DeduplicatingAgentSkillsSource>();
  }

  late final Logger<DeduplicatingAgentSkillsSource> _logger;

  @override
  Future<List<AgentSkill>> getSkills({
    CancellationToken? cancellationToken,
  }) async {
    var allSkills = await this.innerSource
        .getSkillsAsync(cancellationToken)
        ;
    var deduplicated = List<AgentSkill>();
    var seen = Set<String>();
    for (final skill in allSkills) {
      if (seen.add(skill.frontmatter.name)) {
        deduplicated.add(skill);
      } else {
        logDuplicateSkillName(this._logger, skill.frontmatter.name);
      }
    }
    return deduplicated;
  }

  static void logDuplicateSkillName(Logger logger, String skillName) {
    // TODO: implement LogDuplicateSkillName
    // C#:
    throw UnimplementedError('LogDuplicateSkillName not implemented');
  }
}
