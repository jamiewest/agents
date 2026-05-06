import 'package:extensions/system.dart';
import 'package:extensions/logging.dart';
import '../../../../func_typedefs.dart';
import '../agent_skill.dart';
import '../agent_skills_source.dart';
import 'delegating_agent_skills_source.dart';

/// A skill source decorator that filters skills using a caller-supplied
/// predicate.
///
/// Remarks: Skills for which the predicate returns `true` are included in the
/// result; skills for which it returns `false` are excluded and logged at
/// debug level.
class FilteringAgentSkillsSource extends DelegatingAgentSkillsSource {
  /// Initializes a new instance of the [FilteringAgentSkillsSource] class.
  ///
  /// [innerSource] The inner source whose skills will be filtered.
  ///
  /// [predicate] A predicate that determines which skills to include. Skills
  /// for which the predicate returns `true` are kept; others are excluded.
  ///
  /// [loggerFactory] Optional logger factory.
  FilteringAgentSkillsSource(
    AgentSkillsSource innerSource,
    Func<AgentSkill, bool> predicate, {
    LoggerFactory? loggerFactory = null,
  }) : _predicate = predicate,
       super(innerSource) {
    this._logger = (loggerFactory ?? NullLoggerFactory.instance)
        .createLogger<FilteringAgentSkillsSource>();
  }

  final Func<AgentSkill, bool> _predicate;

  late final Logger<FilteringAgentSkillsSource> _logger;

  @override
  Future<List<AgentSkill>> getSkills({
    CancellationToken? cancellationToken,
  }) async {
    var allSkills = await this.innerSource
        .getSkillsAsync(cancellationToken)
        ;
    var filtered = List<AgentSkill>();
    for (final skill in allSkills) {
      if (this._predicate(skill)) {
        filtered.add(skill);
      } else {
        logSkillFiltered(this._logger, skill.frontmatter.name);
      }
    }
    return filtered;
  }

  static void logSkillFiltered(Logger logger, String skillName) {
    // TODO: implement LogSkillFiltered
    // C#:
    throw UnimplementedError('LogSkillFiltered not implemented');
  }
}
