import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import 'chat_client_agent.dart';
import 'chat_client_agent_run_options.dart';

/// Convenience extension methods on [ChatClientAgent] for typed run options.
///
/// These overloads accept [ChatClientAgentRunOptions] directly, improving
/// discoverability over the base [AgentRunOptions] parameter.
extension ChatClientAgentRunOptionsExtension on ChatClientAgent {
  /// Runs the agent with typed [ChatClientAgentRunOptions].
  Future<AgentResponse> runWithOptions(
    AgentSession? session,
    ChatClientAgentRunOptions? options,
    CancellationToken cancellationToken, {
    String? message,
    Iterable<ChatMessage>? messages,
  }) {
    final allMessages = [
      if (message != null) ChatMessage(role: ChatRole.user, contents: [TextContent(message)]),
      ...?messages,
    ];
    return runCore(
      allMessages,
      session: session,
      options: options,
      cancellationToken: cancellationToken,
    );
  }

  /// Runs the agent in streaming mode with typed [ChatClientAgentRunOptions].
  Stream<AgentResponseUpdate> runStreamingWithOptions(
    AgentSession? session,
    ChatClientAgentRunOptions? options,
    CancellationToken cancellationToken, {
    String? message,
    Iterable<ChatMessage>? messages,
  }) {
    final allMessages = [
      if (message != null) ChatMessage(role: ChatRole.user, contents: [TextContent(message)]),
      ...?messages,
    ];
    return runCoreStreaming(
      allMessages,
      session: session,
      options: options,
      cancellationToken: cancellationToken,
    );
  }
}
