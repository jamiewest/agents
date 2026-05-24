import 'package:extensions/system.dart';
import 'agent_skill.dart';
import 'agent_skills_source.dart';

/// A skill source that aggregates multiple child sources, preserving their
/// registration order.
///
/// Skills from each child source are returned in the order the sources were
/// registered, with each source's skills appended sequentially. No
/// deduplication or filtering is applied.
class AggregatingAgentSkillsSource extends AgentSkillsSource {
  /// Creates an [AggregatingAgentSkillsSource] from the given [sources].
  AggregatingAgentSkillsSource(Iterable<AgentSkillsSource> sources)
    : _sources = List<AgentSkillsSource>.of(sources);

  final List<AgentSkillsSource> _sources;

  @override
  Future<List<AgentSkill>> getSkills({
    CancellationToken? cancellationToken,
  }) async {
    var allSkills = <AgentSkill>[];
    for (final source in _sources) {
      final skills = await source.getSkills(
        cancellationToken: cancellationToken,
      );
      allSkills.addAll(skills);
    }
    return allSkills;
  }
}
