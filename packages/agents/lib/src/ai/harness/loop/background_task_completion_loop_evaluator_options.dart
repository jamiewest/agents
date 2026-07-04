/// Provides configuration options for `BackgroundTaskCompletionLoopEvaluator`.
class BackgroundTaskCompletionLoopEvaluatorOptions {
  /// Creates evaluator options.
  BackgroundTaskCompletionLoopEvaluatorOptions();

  /// The template used to build the feedback produced while background tasks
  /// are still running, or `null` to use
  /// `BackgroundTaskCompletionLoopEvaluator.defaultFeedbackMessageTemplate`.
  ///
  /// Any occurrence of
  /// `BackgroundTaskCompletionLoopEvaluator.incompleteTasksPlaceholder` in
  /// the template is replaced, on each evaluation, with a formatted list of
  /// the background tasks that are still running, and any occurrence of
  /// `BackgroundTaskCompletionLoopEvaluator.incompleteTaskCountPlaceholder`
  /// is replaced with the number of those tasks. When a placeholder is
  /// absent the corresponding value is not rendered.
  String? feedbackMessageTemplate;
}
