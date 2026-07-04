import 'package:extensions/system.dart';
import 'agent_skill.dart';
import 'agent_skills_source_context.dart';

/// Abstract base class for skill sources. A skill source provides skills from
/// a specific origin (filesystem, remote server, database, in-memory, etc.).
///
/// Sources are [Disposable] so that pipelines built from decorators can release
/// any resources they own. The default [dispose] does nothing; sources that
/// hold disposable resources override it. Decorators dispose the source they
/// wrap.
abstract class AgentSkillsSource implements Disposable {
  AgentSkillsSource();

  /// Returns the skills provided by this source.
  ///
  /// [context] carries information about the agent and session requesting the
  /// skills.
  Future<List<AgentSkill>> getSkills(
    AgentSkillsSourceContext context, {
    CancellationToken? cancellationToken,
  });

  /// Releases the resources used by this source.
  ///
  /// The default implementation does nothing. Override to release owned
  /// resources.
  @override
  void dispose() {}
}
