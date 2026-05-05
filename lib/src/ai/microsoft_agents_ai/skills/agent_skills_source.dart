import 'package:extensions/system.dart';
import 'agent_skill.dart';

/// Abstract base class for skill sources. A skill source provides skills from
/// a specific origin (filesystem, remote server, database, in-memory, etc.).
abstract class AgentSkillsSource {
  AgentSkillsSource();

  /// Gets the skills provided by this source.
  ///
  /// Returns: A collection of skills from this source.
  ///
  /// [cancellationToken] Cancellation token.
  Future<List<AgentSkill>> getSkills({CancellationToken? cancellationToken});
}
