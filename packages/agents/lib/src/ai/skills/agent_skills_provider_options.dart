import 'agent_skills_provider.dart';

/// Configuration options for [AgentSkillsProvider].
class AgentSkillsProviderOptions {
  AgentSkillsProviderOptions();

  /// Custom system prompt template for advertising skills.
  ///
  /// The template must contain `{skills}` as the placeholder for the
  /// generated skills list. When `null`, a default template is used.
  String? skillsInstructionPrompt;

  /// Whether detailed exception information is included in the error message
  /// returned to the model when a script execution fails.
  ///
  /// When `false` (the default), exceptions propagate to the caller. When
  /// `true`, the exception message is appended to the error string returned
  /// directly to the model, enabling it to retry with different arguments —
  /// but this may disclose raw exception details to the model. Exercise
  /// particular caution when enabling this for skills whose scripts originate
  /// from untrusted or third-party sources: a maliciously crafted script
  /// could throw an exception whose message embeds a prompt-injection
  /// payload, which would then be fed back to the model. Only enable this
  /// when the skills and their scripts come from a trusted source.
  bool includeDetailedErrors = false;

  /// Whether approval is disabled for the
  /// [AgentSkillsProvider.loadSkillToolName] tool.
  ///
  /// When `false` (the default), the tool requires approval before
  /// invocation. When approval is required, auto-approval rules (e.g.
  /// [AgentSkillsProvider.readOnlyToolsAutoApprovalRule] or
  /// [AgentSkillsProvider.allToolsAutoApprovalRule]) can be used to
  /// automatically approve calls.
  bool disableLoadSkillApproval = false;

  /// Whether approval is disabled for the
  /// [AgentSkillsProvider.readSkillResourceToolName] tool.
  ///
  /// When `false` (the default), the tool requires approval before
  /// invocation.
  bool disableReadSkillResourceApproval = false;

  /// Whether approval is disabled for the
  /// [AgentSkillsProvider.runSkillScriptToolName] tool.
  ///
  /// When `false` (the default), the tool requires approval before
  /// invocation.
  bool disableRunSkillScriptApproval = false;
}
