import 'package:extensions/system.dart';
import 'agent_skill.dart';
import 'agent_skills_source.dart';

/// A skill source that aggregates multiple child sources, preserving their
/// registration order.
///
/// Remarks: Skills from each child source are returned in the order the
/// sources were registered, with each source's skills appended sequentially.
/// No deduplication or filtering is applied.
class AggregatingAgentSkillsSource extends AgentSkillsSource {
  /// Initializes a new instance of the [AggregatingAgentSkillsSource] class.
  ///
  /// [sources] The child sources to aggregate.
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
