import 'package:a2a/a2a.dart' hide Logger, A2AAgent;
import 'package:extensions/logging.dart';

import '../a2a_agent.dart';
import '../a2a_agent_options.dart';
import '../../abstractions/ai_agent.dart';
import 'a2a_client_extensions.dart';

/// Extension methods for [A2AAgentCard] that create [AIAgent] instances.
extension A2AAgentCardExtensions on A2AAgentCard {
  /// Creates an [AIAgent] backed by the A2A agent described by this card.
  ///
  /// Supports the
  /// [Curated Registries (Catalog-Based Discovery)](https://github.com/a2aproject/A2A/blob/main/docs/topics/agent-discovery.md#2-curated-registries-catalog-based-discovery)
  /// mechanism.
  AIAgent asAIAgent({
    LoggerFactory? loggerFactory,
  }) {
    final client = A2AClient(url);
    return client.asAIAgentWithOptions(
      A2AAgentOptions(name: name, description: description),
      loggerFactory: loggerFactory,
    );
  }

  /// Creates an [AIAgent] backed by this card, merging [agentOptions] on top.
  ///
  /// Non-null values in [agentOptions] override the card's name and
  /// description. Null values fall back to the card's own fields.
  AIAgent asAIAgentWithOptions(
    A2AAgentOptions agentOptions, {
    LoggerFactory? loggerFactory,
  }) {
    final merged = agentOptions.clone();
    merged.name ??= name;
    merged.description ??= description;

    final client = A2AClient(url);
    return A2AAgent.withOptions(client, merged, loggerFactory: loggerFactory);
  }
}
