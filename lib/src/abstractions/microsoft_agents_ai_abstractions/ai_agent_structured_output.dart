import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'agent_response_t_.dart';
import 'agent_run_options.dart';
import 'agent_session.dart';
import 'ai_agent.dart';

/// Extension methods on [AIAgent] for structured (typed) output.
extension AIAgentStructuredOutputExtensions on AIAgent {
  /// Runs the agent and attempts to deserialize the response as type [T].
  ///
  /// [session] The conversation session, or `null` to start a new one.
  ///
  /// [options] Optional run configuration.
  ///
  /// [cancellationToken] Optional cancellation token.
  ///
  /// [message] Optional single text message to include.
  ///
  /// [messages] Optional additional messages.
  Future<AgentResponseOf<T>> runTyped<T>(
    AgentSession? session, {
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
    String? message,
    Iterable<ChatMessage>? messages,
  }) async {
    final response = await run(
      session,
      options,
      cancellationToken ?? CancellationToken(),
      message: message,
      messages: messages,
    );
    final result =
        AgentResponseOf.deserializeFirstTopLevelObject<T>(response.text);
    return AgentResponseOf<T>(response, result as T);
  }
}
