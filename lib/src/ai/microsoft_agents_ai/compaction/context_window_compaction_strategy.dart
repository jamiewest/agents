import 'package:extensions/system.dart';
import 'package:extensions/logging.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';
import 'compaction_triggers.dart';
import 'pipeline_compaction_strategy.dart';
import 'tool_result_compaction_strategy.dart';
import 'truncation_compaction_strategy.dart';

/// A compaction strategy that derives token thresholds from a model's context
/// window size and maximum output tokens, applying a two-phase compaction
/// pipeline: Tool result eviction ([ToolResultCompactionStrategy]) —
/// collapses old tool call groups into concise summaries when the token count
/// exceeds the [ToolEvictionThreshold]. Truncation
/// ([TruncationCompactionStrategy]) — removes the oldest non-system message
/// groups when the token count exceeds the [TruncationThreshold].
///
/// Remarks: The input budget is defined as `maxContextWindowTokens -
/// maxOutputTokens`, representing the maximum number of tokens available for
/// the conversation input (including system messages, tools, and history).
/// This strategy is a convenience wrapper around [PipelineCompactionStrategy]
/// that automates threshold calculation from model specifications.
class ContextWindowCompactionStrategy extends CompactionStrategy {
  /// Initializes a new instance of the [ContextWindowCompactionStrategy] class.
  ///
  /// [maxContextWindowTokens] The maximum number of tokens the model's context
  /// window supports (e.g., 1,050,000 for gpt-5.4).
  ///
  /// [maxOutputTokens] The maximum number of output tokens the model can
  /// generate per response (e.g., 128,000 for gpt-5.4).
  ///
  /// [toolEvictionThreshold] The fraction of the input budget (0.0, 1.0] at
  /// which tool result eviction triggers. Defaults to
  /// [DefaultToolEvictionThreshold] (0.5).
  ///
  /// [truncationThreshold] The fraction of the input budget (0.0, 1.0] at which
  /// truncation triggers. Defaults to [DefaultTruncationThreshold] (0.8). Must
  /// be greater than or equal to `toolEvictionThreshold`.
  ContextWindowCompactionStrategy(
    int maxContextWindowTokens,
    int maxOutputTokens,
    {double? toolEvictionThreshold = null, double? truncationThreshold = null, },
  ) :
      maxContextWindowTokens = maxContextWindowTokens,
      maxOutputTokens = maxOutputTokens {
    validateThreshold(toolEvictionThreshold, 'toolEvictionThreshold');
    validateThreshold(truncationThreshold, 'truncationThreshold');
    if (truncationThreshold < toolEvictionThreshold) {
      throw ArgumentError.value('truncationThreshold', truncationThreshold,
                'Truncation threshold (${truncationThreshold}) must be greater than or equal to tool eviction threshold (${toolEvictionThreshold}).');
    }
    this.inputBudgetTokens = maxContextWindowTokens - maxOutputTokens;
    this.toolEvictionThreshold = toolEvictionThreshold;
    this.truncationThreshold = truncationThreshold;
    var toolEvictionTokens = (int)(this.inputBudgetTokens * toolEvictionThreshold);
    var truncationTokens = (int)(this.inputBudgetTokens * truncationThreshold);
    this._pipeline = pipelineCompactionStrategy(
            toolResultCompactionStrategy(
                trigger: CompactionTriggers.tokensExceed(toolEvictionTokens),
                minimumPreservedGroups: 2),
            truncationCompactionStrategy(
                trigger: CompactionTriggers.tokensExceed(truncationTokens),
                minimumPreservedGroups: 2));
  }

  late final PipelineCompactionStrategy _pipeline;

  /// Gets the maximum context window size in tokens.
  final int maxContextWindowTokens;

  /// Gets the maximum output tokens per response.
  final int maxOutputTokens;

  /// Gets the computed input budget in tokens ([MaxContextWindowTokens] minus
  /// [MaxOutputTokens]).
  late final int inputBudgetTokens;

  /// Gets the fraction of the input budget at which tool result eviction
  /// triggers.
  late final double toolEvictionThreshold;

  /// Gets the fraction of the input budget at which truncation triggers.
  late final double truncationThreshold;

  @override
  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  ) async  {
    return await this._pipeline.compactAsync(
      index,
      logger,
      cancellationToken,
    ) ;
  }

  static void validateThreshold(double value, String paramName, ) {
    if (value is <= 0.0 or > 1.0) {
      throw ArgumentError.value(
        paramName,
        value,
        "Threshold must be in the range (0.0, 1.0].",
      );
    }
  }
}
