import 'package:extensions/ai.dart';

/// The result produced by a [LoopEvaluator] after an agent iteration: whether
/// the loop should re-invoke the wrapped agent and, optionally, the feedback or
/// explicit messages that should inform the next iteration.
///
/// An evaluator is concerned only with the judgment (continue or stop) and what
/// to carry forward. In the common case it returns a feedback string and lets
/// the loop decide how that feedback is turned into the next input. For full
/// control, [proceedWithMessages] supplies the exact messages to send next,
/// bypassing the loop's feedback and message construction.
class LoopEvaluation {
  LoopEvaluation._(this.shouldReinvoke, this.feedback, this.messages);

  static final LoopEvaluation _stop = LoopEvaluation._(false, null, null);

  /// Whether the loop should run the wrapped agent again.
  final bool shouldReinvoke;

  /// Feedback describing what is missing or what the agent should do next, or
  /// `null` when no feedback was produced.
  ///
  /// Only meaningful when [shouldReinvoke] is `true`.
  final String? feedback;

  /// The explicit messages to send on the next iteration, or `null` when the
  /// loop should build the next input from feedback instead.
  ///
  /// Consumed by the loop agent. When non-`null` the messages are sent verbatim
  /// and the loop does not apply its feedback or message construction. Only
  /// meaningful when [shouldReinvoke] is `true`.
  final List<ChatMessage>? messages;

  /// Creates an evaluation that stops the loop and returns the latest response
  /// to the caller.
  static LoopEvaluation stop() => _stop;

  /// Creates an evaluation that re-invokes the wrapped agent, optionally
  /// carrying [feedback] forward.
  ///
  /// `null`, empty, or whitespace [feedback] is treated as no feedback. Named
  /// `proceed` rather than `continue` because the latter is a Dart keyword;
  /// mirrors C# `LoopEvaluation.Continue`.
  static LoopEvaluation proceed([String? feedback]) => LoopEvaluation._(
    true,
    (feedback == null || feedback.trim().isEmpty) ? null : feedback,
    null,
  );

  /// Creates an evaluation that re-invokes the wrapped agent with the specified
  /// [messages], bypassing the loop's feedback and message construction.
  ///
  /// Use this for full control over the next input (for example to send
  /// non-user roles, multiple messages, or non-text content). Mirrors C#
  /// `LoopEvaluation.ContinueWithMessages`.
  static LoopEvaluation proceedWithMessages(Iterable<ChatMessage> messages) =>
      LoopEvaluation._(true, null, List<ChatMessage>.of(messages));
}
