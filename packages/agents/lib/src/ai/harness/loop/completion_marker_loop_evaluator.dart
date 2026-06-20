import 'package:extensions/system.dart';

import 'completion_marker_loop_evaluator_options.dart';
import 'loop_context.dart';
import 'loop_evaluation.dart';
import 'loop_evaluator.dart';

/// A [LoopEvaluator] that stops the loop once a configured marker string appears
/// in the agent's latest response, and otherwise continues with feedback asking
/// the agent to keep working and to emit the marker when done.
class CompletionMarkerLoopEvaluator extends LoopEvaluator {
  /// The placeholder token replaced with the configured completion marker.
  static const String completionMarkerPlaceholder = '{completion_marker}';

  /// The placeholder token replaced, on each evaluation, with the text of the
  /// agent's latest response.
  static const String lastResponsePlaceholder = '{last_response}';

  /// The default template used to build the feedback produced while the
  /// completion marker is absent.
  static const String defaultFeedbackMessageTemplate =
      'Continue working on the request. When you have fully completed the '
      'task, end your response with the marker '
      "'$completionMarkerPlaceholder' to indicate completion.";

  /// Creates a [CompletionMarkerLoopEvaluator].
  ///
  /// [completionMarker] is the marker that stops the loop once it appears in the
  /// agent's latest response text. Throws [ArgumentError] if it is empty or
  /// whitespace.
  CompletionMarkerLoopEvaluator(
    String completionMarker, {
    CompletionMarkerLoopEvaluatorOptions? options,
  }) : _completionMarker = _checkNotBlank(completionMarker),
       _feedbackMessageTemplate =
           (options?.feedbackMessageTemplate ?? defaultFeedbackMessageTemplate)
               .replaceAll(completionMarkerPlaceholder, completionMarker);

  final String _completionMarker;
  final String _feedbackMessageTemplate;

  @override
  Future<LoopEvaluation> evaluate(
    LoopContext context, {
    CancellationToken? cancellationToken,
  }) {
    final text = context.lastResponse.text;
    if (text.contains(_completionMarker)) {
      return Future.value(LoopEvaluation.stop());
    }
    final feedback = _feedbackMessageTemplate.replaceAll(
      lastResponsePlaceholder,
      text,
    );
    return Future.value(LoopEvaluation.proceed(feedback));
  }

  static String _checkNotBlank(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        'completionMarker',
        'must not be empty or whitespace',
      );
    }
    return value;
  }
}
