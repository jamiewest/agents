import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import 'compaction_message_index.dart';
import 'compaction_strategy.dart';
import 'compaction_triggers.dart';
import 'pipeline_compaction_strategy.dart';
import 'tool_result_compaction_strategy.dart';
import 'truncation_compaction_strategy.dart';

/// A compaction strategy that derives token thresholds from a model's context
/// window size and maximum output tokens, applying tool-result eviction before
/// truncation.
class ContextWindowCompactionStrategy extends CompactionStrategy {
  ContextWindowCompactionStrategy(
    this.maxContextWindowTokens,
    this.maxOutputTokens, {
    double? toolEvictionThreshold,
    double? truncationThreshold,
  }) : toolEvictionThreshold =
           toolEvictionThreshold ?? defaultToolEvictionThreshold,
       truncationThreshold = truncationThreshold ?? defaultTruncationThreshold,
       super(
         CompactionTriggers.tokensExceed(
           maxContextWindowTokens - maxOutputTokens,
         ),
       ) {
    if (maxContextWindowTokens <= 0) {
      throw ArgumentError.value(
        maxContextWindowTokens,
        'maxContextWindowTokens',
        'Context window token count must be positive.',
      );
    }
    if (maxOutputTokens < 0 || maxOutputTokens >= maxContextWindowTokens) {
      throw ArgumentError.value(
        maxOutputTokens,
        'maxOutputTokens',
        'Maximum output tokens must be non-negative and less than the context window.',
      );
    }

    validateThreshold(this.toolEvictionThreshold, 'toolEvictionThreshold');
    validateThreshold(this.truncationThreshold, 'truncationThreshold');
    if (this.truncationThreshold < this.toolEvictionThreshold) {
      throw ArgumentError.value(
        this.truncationThreshold,
        'truncationThreshold',
        'Truncation threshold must be greater than or equal to tool eviction threshold.',
      );
    }

    inputBudgetTokens = maxContextWindowTokens - maxOutputTokens;
    final toolEvictionTokens = (inputBudgetTokens * this.toolEvictionThreshold)
        .floor();
    final truncationTokens = (inputBudgetTokens * this.truncationThreshold)
        .floor();

    _pipeline = PipelineCompactionStrategy([
      ToolResultCompactionStrategy(
        CompactionTriggers.tokensExceed(toolEvictionTokens),
        minimumPreservedGroups: 2,
      ),
      TruncationCompactionStrategy(
        CompactionTriggers.tokensExceed(truncationTokens),
        minimumPreservedGroups: 2,
      ),
    ]);
  }

  static const double defaultToolEvictionThreshold = 0.5;
  static const double defaultTruncationThreshold = 0.8;

  late final PipelineCompactionStrategy _pipeline;

  final int maxContextWindowTokens;
  final int maxOutputTokens;
  late final int inputBudgetTokens;
  final double toolEvictionThreshold;
  final double truncationThreshold;

  @override
  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  ) {
    return _pipeline.compact(
      index,
      logger: logger,
      cancellationToken: cancellationToken,
    );
  }

  static void validateThreshold(double value, String paramName) {
    if (value <= 0.0 || value > 1.0) {
      throw ArgumentError.value(
        value,
        paramName,
        'Threshold must be in the range (0.0, 1.0].',
      );
    }
  }
}
