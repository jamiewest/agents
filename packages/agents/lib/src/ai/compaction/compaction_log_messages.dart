import 'package:extensions/logging.dart';

/// Logging extensions for compaction diagnostics.
extension CompactionLogMessages on Logger {
  /// Logs when compaction is skipped because the trigger condition was not met.
  void logCompactionSkipped(String strategyName) {
    if (!isEnabled(LogLevel.debug)) return;
    logDebug('Compaction skipped. Strategy: $strategyName.');
  }

  /// Logs compaction completion with before/after metrics.
  void logCompactionCompleted(
    String strategyName,
    int durationMs,
    int beforeMessages,
    int afterMessages,
    int beforeGroups,
    int afterGroups,
    int beforeTokens,
    int afterTokens,
  ) {
    if (!isEnabled(LogLevel.debug)) return;
    logDebug(
      'Compaction completed. Strategy: $strategyName. '
      'Duration: ${durationMs}ms. '
      'Messages: $beforeMessages -> $afterMessages. '
      'Groups: $beforeGroups -> $afterGroups. '
      'Tokens: $beforeTokens -> $afterTokens.',
    );
  }

  /// Logs when the compaction provider skips compaction.
  void logCompactionProviderSkipped(String reason) {
    if (!isEnabled(LogLevel.debug)) return;
    logDebug('Compaction provider skipped. Reason: $reason.');
  }

  /// Logs when the compaction provider begins applying a compaction strategy.
  void logCompactionProviderApplying(int messageCount, String strategyName) {
    if (!isEnabled(LogLevel.debug)) return;
    logDebug(
      'Compaction provider applying. '
      'Messages: $messageCount. Strategy: $strategyName.',
    );
  }

  /// Logs when the compaction provider has applied compaction.
  void logCompactionProviderApplied(int beforeMessages, int afterMessages) {
    if (!isEnabled(LogLevel.debug)) return;
    logDebug(
      'Compaction provider applied. Messages: $beforeMessages -> $afterMessages.',
    );
  }

  /// Logs when a summarization LLM call is starting.
  void logSummarizationStarting(
    int groupCount,
    int messageCount,
    String chatClientType,
  ) {
    if (!isEnabled(LogLevel.debug)) return;
    logDebug(
      'Summarization starting. '
      'Groups: $groupCount. Messages: $messageCount. Client: $chatClientType.',
    );
  }

  /// Logs when a summarization LLM call has completed.
  void logSummarizationCompleted(int summaryLength, int insertIndex) {
    if (!isEnabled(LogLevel.debug)) return;
    logDebug(
      'Summarization completed. '
      'Summary length: $summaryLength. Insert index: $insertIndex.',
    );
  }

  /// Logs when a summarization LLM call fails and groups are restored.
  void logSummarizationFailed(int groupCount, String errorMessage) {
    logWarning(
      'Summarization failed. Groups restored: $groupCount. Error: $errorMessage.',
    );
  }
}
