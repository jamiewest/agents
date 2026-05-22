import '../../../abstractions/ai_agent.dart';
import '../../../func_typedefs.dart';
import 'background_agents_provider.dart';

/// Options controlling the behavior of [BackgroundAgentsProvider].
class BackgroundAgentsProviderOptions {
  BackgroundAgentsProviderOptions();

  /// Custom instructions provided to the agent for using the background agent
  /// tools.
  ///
  /// Use the `{background_agents}` placeholder to allow the provider to inject
  /// the formatted list of available background agents.
  String? instructions;

  /// Custom function that builds the agent list text to append to
  /// instructions.
  Func<Map<String, AIAgent>, String>? agentListBuilder;
}
