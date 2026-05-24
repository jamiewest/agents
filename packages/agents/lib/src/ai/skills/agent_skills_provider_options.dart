import 'agent_skills_provider.dart';

/// Configuration options for [AgentSkillsProvider].
class AgentSkillsProviderOptions {
  AgentSkillsProviderOptions();

  /// Custom system prompt template for advertising skills.
  ///
  /// The template must contain `{skills}` as the placeholder for the generated
  /// skills list, `{resource_instructions}` for resource instructions, and
  /// `{script_instructions}` for script instructions. When `null`, a default
  /// template is used.
  String? skillsInstructionPrompt;

  /// Whether script execution requires approval.
  ///
  /// When `true`, script execution is blocked until approved. Defaults to
  /// `false`.
  bool scriptApproval = false;

  /// Whether caching of tools and instructions is disabled.
  ///
  /// When `false` (the default), the provider caches the tools and
  /// instructions after the first build and returns the cached instance on
  /// subsequent calls. Set to `true` to rebuild tools and instructions on
  /// every invocation.
  bool disableCaching = false;
}
