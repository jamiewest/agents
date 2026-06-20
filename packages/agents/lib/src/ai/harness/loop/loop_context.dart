import 'package:extensions/ai.dart';

import '../../../abstractions/agent_response.dart';
import '../../../abstractions/agent_run_options.dart';
import '../../../abstractions/agent_session.dart';
import '../../../abstractions/ai_agent.dart';

/// The per-run state that a [LoopEvaluator] uses to decide whether a loop agent
/// should re-invoke the wrapped agent and what feedback to provide.
///
/// A single [LoopContext] instance is created for each loop run and is reused
/// across iterations, with [iteration] and [lastResponse] updated before each
/// evaluation. Because evaluator instances are expected to be stateless and may
/// be shared across concurrent runs, any per-run mutable state must be stored on
/// this context — for example via [additionalProperties] — rather than in fields
/// on the evaluator itself.
class LoopContext {
  /// Creates a [LoopContext].
  ///
  /// [agent] is the wrapped agent being looped, [session] the session used for
  /// the loop, [initialMessages] the messages passed in for the first
  /// iteration, and [lastResponse] the response produced by the iteration that
  /// just completed. [runOptions] are the options passed to the loop run, if
  /// any.
  LoopContext(
    this.agent,
    this.session,
    this.initialMessages,
    this.lastResponse, {
    this.runOptions,
  });

  /// The wrapped agent that is being looped.
  final AIAgent agent;

  /// The session used for the loop.
  ///
  /// By default the same session is reused across every iteration so
  /// conversation continuity is preserved. The loop replaces it before each
  /// re-invocation when fresh-context-per-iteration is enabled.
  AgentSession session;

  /// The messages that were passed in for the first iteration of the loop.
  final List<ChatMessage> initialMessages;

  /// The options that were passed to the loop run, if any.
  final AgentRunOptions? runOptions;

  /// The number of completed agent runs so far (1-based after the first run).
  int iteration = 0;

  /// The response produced by the iteration that just completed.
  AgentResponse lastResponse;

  /// The feedback accumulated across iterations so far, one entry per re-invoked
  /// iteration in order.
  ///
  /// Each entry is the feedback supplied by the evaluator that requested the
  /// corresponding re-invocation, or `null` when that iteration produced no
  /// feedback string. Owned and populated by the loop agent; evaluators may read
  /// it to reason over prior feedback.
  List<String?> feedback = const [];

  /// A mutable bag of per-run state shared across iterations and available to
  /// every evaluator.
  ///
  /// Owned by the loop run (not by any evaluator instance) so that evaluators
  /// can remain stateless.
  final AdditionalPropertiesDictionary additionalProperties =
      AdditionalPropertiesDictionary();
}
