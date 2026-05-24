import 'package:extensions/system.dart';
import 'agent_skill.dart';
import 'agent_skills_source.dart';

/// A skill source that holds [AgentSkill] instances in memory.
class AgentInMemorySkillsSource extends AgentSkillsSource {
  /// Creates an [AgentInMemorySkillsSource] with the given [skills].
  AgentInMemorySkillsSource(Iterable<AgentSkill> skills)
    : _skills = skills.toList();

  final List<AgentSkill> _skills;

  @override
  Future<List<AgentSkill>> getSkills({CancellationToken? cancellationToken}) {
    return Future.value(_skills);
  }
}
