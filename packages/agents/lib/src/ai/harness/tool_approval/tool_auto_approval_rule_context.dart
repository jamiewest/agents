import 'package:extensions/ai.dart';

import '../../../abstractions/agent_run_options.dart';
import '../../../abstractions/agent_session.dart';
import '../../../abstractions/ai_agent.dart';

/// The context handed to an auto-approval rule when a tool call requires
/// approval.
///
/// A rule receives the function call under consideration along with the agent,
/// session and request that produced it, so a heuristic can take more than the
/// call itself into account (for example approving a read-only tool only for a
/// particular session, or only when the caller supplied specific run options).
class ToolAutoApprovalRuleContext {
  /// Creates a context for [functionCallContent] raised by [agent].
  ToolAutoApprovalRuleContext({
    required this.functionCallContent,
    required this.agent,
    required this.session,
    required this.requestMessages,
    required this.runOptions,
  });

  /// The function call that requires approval.
  final FunctionCallContent functionCallContent;

  /// The agent that surfaced the approval request.
  final AIAgent agent;

  /// The session the run is executing under, when there is one.
  final AgentSession? session;

  /// The messages that were sent to the inner agent for this turn.
  final Iterable<ChatMessage> requestMessages;

  /// The run options the caller supplied, when there were any.
  final AgentRunOptions? runOptions;
}

/// A heuristic that decides whether a tool call may be approved without
/// prompting the user.
///
/// Returns `true` to auto-approve the call, or `false` to continue evaluating
/// the next rule.
typedef ToolAutoApprovalRule =
    Future<bool> Function(ToolAutoApprovalRuleContext context);
