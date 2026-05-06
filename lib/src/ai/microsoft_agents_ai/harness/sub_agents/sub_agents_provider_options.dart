import 'package:extensions/ai.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../../../func_typedefs.dart';
import 'sub_agents_provider.dart';

/// Options controlling the behavior of [SubAgentsProvider].
class SubAgentsProviderOptions {
  SubAgentsProviderOptions();

  /// Gets or sets custom instructions provided to the agent for using the
  /// sub-agent tools.
  ///
  /// Remarks: Use the `{sub_agents}` placeholder to allow the provider to
  /// inject the formatted list of available sub agents.
  String? instructions;

  /// Gets or sets a custom function that builds the agent list text to append
  /// to instructions.
  Func<Map<String, AIAgent>, String>? agentListBuilder;
}
