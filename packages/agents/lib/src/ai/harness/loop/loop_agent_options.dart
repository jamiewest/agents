import 'package:extensions/system.dart';

import '../../../abstractions/agent_session.dart';

/// A callback invoked whenever the loop agent creates a new session, so the
/// caller can capture the latest session.
typedef SessionCreatedCallback =
    Future<void> Function(
      AgentSession session,
      CancellationToken? cancellationToken,
    );

/// Configuration options for a loop agent.
class LoopAgentOptions {
  /// The global safety cap on the number of times the wrapped agent is invoked
  /// in a single loop run, or `null` to use the loop agent's default.
  ///
  /// This is an absolute upper bound that applies regardless of the configured
  /// evaluators. An evaluator may stop the loop earlier, but no evaluator can
  /// cause the loop to exceed this cap.
  int? maxIterations;

  /// Whether each re-invocation restarts from a clean context: the original
  /// input messages plus an aggregated feedback log, rather than the latest
  /// feedback appended to the prior conversation. Defaults to `false`.
  ///
  /// This rebuilds the input messages each iteration and resets the session
  /// before each re-invocation. When the loop owns the session it creates a new
  /// one each iteration; when the caller supplies a session, the loop serializes
  /// it once at the start of the run and restores a fresh clone before each
  /// re-invocation (requiring the wrapped agent to support session
  /// serialization).
  bool freshContextPerIteration = false;

  /// The author name stamped on the loop-synthesized "on-behalf-of" messages
  /// that the loop injects for re-invocations, or `null` to leave them
  /// unattributed. Defaults to `null`.
  ///
  /// Applied only to messages the loop synthesizes itself; messages supplied
  /// explicitly by an evaluator are left untouched, and the caller's original
  /// input messages are never modified.
  String? onBehalfOfAuthorName;

  /// Whether the on-behalf-of messages the loop injects for re-invocations are
  /// omitted from the output surfaced back to the caller. Defaults to `false`.
  ///
  /// The messages are still sent to the wrapped agent. Has no effect when
  /// [nonStreamingReturnsLastResponseOnly] causes a non-streaming run to return
  /// only the final response.
  bool excludeOnBehalfOfMessages = false;

  /// Whether a non-streaming run returns only the final iteration's response
  /// instead of the aggregated transcript of every iteration. Defaults to
  /// `false`.
  ///
  /// Affects non-streaming runs only; streaming runs always yield every
  /// iteration's updates.
  bool nonStreamingReturnsLastResponseOnly = false;

  /// An optional callback invoked whenever the loop agent creates a new session,
  /// so the caller can capture the latest session. Defaults to `null`.
  ///
  /// Invoked with each session the loop itself creates; not invoked for a
  /// caller-supplied session.
  SessionCreatedCallback? sessionCreatedCallback;
}
