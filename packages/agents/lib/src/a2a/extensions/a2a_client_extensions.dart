import 'package:a2a/a2a.dart' hide Logger, A2AAgent;
import 'package:extensions/logging.dart';

import '../a2a_agent.dart';
import '../a2a_agent_options.dart';

/// Extension methods for [A2AClient] that create [A2AAgent] instances.
extension A2AClientExtensions on A2AClient {
  /// Creates an [A2AAgent] backed by this client.
  ///
  /// Supports the
  /// [Direct Configuration / Private Discovery](https://github.com/a2aproject/A2A/blob/main/docs/topics/agent-discovery.md#3-direct-configuration--private-discovery)
  /// mechanism.
  A2AAgent asAIAgent({
    String? id,
    String? name,
    String? description,
    LoggerFactory? loggerFactory,
  }) => A2AAgent(
    this,
    id: id,
    name: name,
    description: description,
    loggerFactory: loggerFactory,
  );

  /// Creates an [A2AAgent] backed by this client using explicit options.
  A2AAgent asAIAgentWithOptions(
    A2AAgentOptions options, {
    LoggerFactory? loggerFactory,
  }) => A2AAgent.withOptions(this, options, loggerFactory: loggerFactory);
}
