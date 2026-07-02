import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/ai_context_provider.dart';
import 'package:extensions/ai.dart';

/// Context passed to [AIContextProvider.invoked].
class InvokedContext {
  InvokedContext(
    this.agent,
    this.session,
    this.requestMessages, {
    this.responseMessages,
    this.invokeException,
  });

  /// The agent that was invoked.
  final AIAgent agent;

  /// The session associated with the agent invocation.
  final AgentSession? session;

  /// The accumulated request messages used by the agent for this invocation.
  final Iterable<ChatMessage> requestMessages;

  /// The response messages generated during this invocation.
  final Iterable<ChatMessage>? responseMessages;

  /// The exception thrown during the invocation, if any.
  final Exception? invokeException;
}
