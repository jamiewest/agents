import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../agent_skill.dart';
import '../agent_skills_source.dart';
import 'delegating_agent_skills_source.dart';

/// A skill source decorator that removes duplicate skills by name, keeping
/// only the first occurrence.
class DeduplicatingAgentSkillsSource extends DelegatingAgentSkillsSource {
  DeduplicatingAgentSkillsSource(
    AgentSkillsSource innerSource, {
    LoggerFactory? loggerFactory,
  }) : _logger = (loggerFactory ?? NullLoggerFactory.instance).createLogger(
         'DeduplicatingAgentSkillsSource',
       ),
       super(innerSource);

  final Logger _logger;

  @override
  Future<List<AgentSkill>> getSkills({
    CancellationToken? cancellationToken,
  }) async {
    final allSkills = await innerSource.getSkills(
      cancellationToken: cancellationToken,
    );
    final deduplicated = <AgentSkill>[];
    final seen = <String>{};
    for (final skill in allSkills) {
      if (seen.add(skill.frontmatter.name)) {
        deduplicated.add(skill);
      } else {
        logDuplicateSkillName(_logger, skill.frontmatter.name);
      }
    }
    return deduplicated;
  }

  static void logDuplicateSkillName(Logger logger, String skillName) {
    if (logger.isEnabled(LogLevel.debug)) {
      logger.logDebug('Duplicate skill name skipped: $skillName.');
    }
  }
}
