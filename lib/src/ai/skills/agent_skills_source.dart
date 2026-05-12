import 'package:extensions/system.dart';
import 'agent_skill.dart';

/// Abstract base class for skill sources. A skill source provides skills from
/// a specific origin (filesystem, remote server, database, in-memory, etc.).
abstract class AgentSkillsSource {
  AgentSkillsSource();

  /// Returns the skills provided by this source.
  Future<List<AgentSkill>> getSkills({CancellationToken? cancellationToken});
}
