import 'package:extensions/system.dart';
import 'agent_skill.dart';
import 'agent_skills_source.dart';

/// A skill source that holds [AgentSkill] instances in memory.
class AgentInMemorySkillsSource extends AgentSkillsSource {
  /// Initializes a new instance of the [AgentInMemorySkillsSource] class.
  ///
  /// [skills] The skills to include in this source.
  AgentInMemorySkillsSource(Iterable<AgentSkill> skills)
      : _skills = skills.toList();

  final List<AgentSkill> _skills;

  @override
  Future<List<AgentSkill>> getSkills({CancellationToken? cancellationToken}) {
    return Future.value(this._skills);
  }
}
