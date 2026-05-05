import 'package:extensions/ai.dart';

import '../../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';

/// Provides specialized run options for [ChatClientAgent] instances,
/// extending the base agent run options with chat-specific configuration.
class ChatClientAgentRunOptions extends AgentRunOptions {
  /// Creates a [ChatClientAgentRunOptions] with optional chat options.
  ChatClientAgentRunOptions({ChatOptions? chatOptions})
      : chatOptions = chatOptions;

  /// Chat options to apply for this specific invocation.
  ///
  /// These are merged with the agent's default chat options; per-invocation
  /// values take precedence over agent-level defaults.
  ChatOptions? chatOptions;

  /// A factory that can wrap (typically via decorators) the [ChatClient] on a
  /// per-request basis.
  ChatClient Function(ChatClient)? chatClientFactory;

  @override
  AgentRunOptions clone() => ChatClientAgentRunOptions(chatOptions: chatOptions)
    ..chatClientFactory = chatClientFactory;
}
