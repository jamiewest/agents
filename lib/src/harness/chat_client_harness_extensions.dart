import 'package:extensions/ai.dart';

import 'harness_agent.dart';
import 'harness_agent_options.dart';

/// Provides extension methods for creating a [HarnessAgent] from a
/// [ChatClient].
extension ChatClientHarnessExtensions on ChatClient {
  /// Creates a new [HarnessAgent] that wraps this [ChatClient] with a
  /// pre-configured pipeline.
  HarnessAgent asHarnessAgent(
    int maxContextWindowTokens,
    int maxOutputTokens, {
    HarnessAgentOptions? options,
  }) {
    return HarnessAgent(
      this,
      maxContextWindowTokens,
      maxOutputTokens,
      options: options,
    );
  }
}
