import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/chat_history_provider.dart';
import 'package:extensions/ai.dart';

import 'ai_context.dart';

/// Context passed to [ChatHistoryProvider.invoking] and
/// `AIContextProvider.invoking` at the start of an agent invocation.
///
/// Merges the upstream C# nested `ChatHistoryProvider.InvokingContext` and
/// `AIContextProvider.InvokingContext` types into one shared class (Dart has
/// no nested classes, so the duplicated names would otherwise collide).
/// Chat-history providers consume [requestMessages]; AI-context providers
/// consume [aiContext], which is only populated on that path.
class InvokingContext {
  /// Creates an [InvokingContext].
  InvokingContext(
    this.agent,
    this.session,
    this.requestMessages, [
    this.aiContext,
  ]);

  /// The agent being invoked.
  final AIAgent agent;

  /// The session associated with the agent invocation.
  final AgentSession? session;

  /// The messages to be used by the agent for this invocation.
  Iterable<ChatMessage>? requestMessages;

  /// The [AIContext] being built for the current invocation, when invoked
  /// through the AI-context-provider pipeline.
  final AIContext? aiContext;
}
