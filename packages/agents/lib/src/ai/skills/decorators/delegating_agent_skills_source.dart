import 'package:extensions/system.dart';
import '../agent_skill.dart';
import '../agent_skills_source.dart';

/// Provides an abstract base class for skill sources that delegate operations
/// to an inner source while allowing for extensibility and customization.
///
/// [DelegatingAgentSkillsSource] implements the decorator pattern for
/// [AgentSkillsSource], enabling the creation of source pipelines where each
/// layer can add functionality (caching, deduplication, filtering, etc.)
/// while delegating core operations to an underlying source.
abstract class DelegatingAgentSkillsSource extends AgentSkillsSource {
  /// Creates a [DelegatingAgentSkillsSource] wrapping [innerSource].
  DelegatingAgentSkillsSource(this.innerSource);

  /// Gets the inner skill source that receives delegated operations.
  final AgentSkillsSource innerSource;

  @override
  Future<List<AgentSkill>> getSkills({CancellationToken? cancellationToken}) {
    return innerSource.getSkills(cancellationToken: cancellationToken);
  }
}
