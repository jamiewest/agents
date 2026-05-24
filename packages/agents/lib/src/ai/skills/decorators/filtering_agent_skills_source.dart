import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../../../func_typedefs.dart';
import '../agent_skill.dart';
import 'delegating_agent_skills_source.dart';

/// A skill source decorator that filters skills using a caller-supplied
/// predicate.
class FilteringAgentSkillsSource extends DelegatingAgentSkillsSource {
  FilteringAgentSkillsSource(
    super.innerSource,
    Func<AgentSkill, bool> predicate, {
    LoggerFactory? loggerFactory,
  }) : _predicate = predicate,
       _logger = (loggerFactory ?? NullLoggerFactory.instance).createLogger(
         'FilteringAgentSkillsSource',
       );

  final Func<AgentSkill, bool> _predicate;
  final Logger _logger;

  @override
  Future<List<AgentSkill>> getSkills({
    CancellationToken? cancellationToken,
  }) async {
    final allSkills = await innerSource.getSkills(
      cancellationToken: cancellationToken,
    );
    final filtered = <AgentSkill>[];
    for (final skill in allSkills) {
      if (_predicate(skill)) {
        filtered.add(skill);
      } else {
        logSkillFiltered(_logger, skill.frontmatter.name);
      }
    }
    return filtered;
  }

  static void logSkillFiltered(Logger logger, String skillName) {
    if (logger.isEnabled(LogLevel.debug)) {
      logger.logDebug('Skill filtered: $skillName.');
    }
  }
}
