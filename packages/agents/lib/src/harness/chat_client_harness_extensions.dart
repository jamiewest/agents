import 'package:extensions/ai.dart';

import 'harness_agent.dart';
import 'harness_agent_options.dart';

/// Provides extension methods for creating a [HarnessAgent] from a
/// [ChatClient].
extension ChatClientHarnessExtensions on ChatClient {
  /// Creates a new [HarnessAgent] that wraps this [ChatClient] with a
  /// pre-configured pipeline including function invocation,
  /// per-service-call chat history persistence, and in-loop compaction.
  ///
  /// The [maxContextWindowTokens] is the maximum number of tokens the
  /// model's context window supports (e.g., 1,050,000 for gpt-5.4),
  /// used to configure the compaction strategy.
  ///
  /// The [maxOutputTokens] is the maximum number of output tokens the
  /// model can generate per response (e.g., 128,000 for gpt-5.4),
  /// used to configure the compaction strategy.
  ///
  /// The [options] provides optional configuration for the agent,
  /// including an instructions override, tools, additional context
  /// providers, and a chat history provider. When null, the agent uses
  /// built-in default settings.
  ///
  /// Returns a new [HarnessAgent] instance.
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
