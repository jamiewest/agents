import 'package:extensions/ai.dart';

import 'agent_run_options.dart';
import 'agent_session.dart';
import 'ai_agent.dart';

/// Provides context for an in-flight agent run.
class AgentRunContext {
  AgentRunContext(
    this.agent,
    this.session,
    this.requestMessages,
    this.runOptions,
  );

  /// The [AIAgent] executing the current run.
  final AIAgent agent;

  /// The [AgentSession] associated with the current run, if any.
  final AgentSession? session;

  /// The request messages passed into the current run.
  final List<ChatMessage> requestMessages;

  /// The [AgentRunOptions] passed to the current run.
  final AgentRunOptions? runOptions;
}
