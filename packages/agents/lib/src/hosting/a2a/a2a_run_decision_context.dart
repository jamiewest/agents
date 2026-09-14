import 'package:a2a/a2a.dart';

/// Provides context for a custom A2A run-mode decision.
///
/// Passed to the delegate supplied to [AgentRunMode.returnTaskWhen] so it
/// can inspect the incoming A2A request when deciding whether the response is
/// returned as an `AgentTask` or an `AgentMessage`.
class A2ARunDecisionContext {
  /// Creates a decision context wrapping [requestContext].
  A2ARunDecisionContext(this.requestContext);

  /// The request context of the incoming A2A request that triggered this run.
  final A2ARequestContext requestContext;
}
