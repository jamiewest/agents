import 'package:extensions/system.dart';
import 'package:extensions/logging.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';
import 'compaction_trigger.dart';

/// A compaction strategy that executes a sequential pipeline of
/// [CompactionStrategy] instances against the same [CompactionMessageIndex].
///
/// Each strategy in the pipeline operates on the result of the previous one,
/// enabling composed behaviors such as summarizing older messages first and
/// then truncating to fit a token budget. The pipeline itself always executes
/// while each child strategy evaluates its own trigger independently to decide
/// whether it should compact.
class PipelineCompactionStrategy extends CompactionStrategy {
  /// Creates a [PipelineCompactionStrategy] from an ordered [strategies]
  /// sequence and optional [trigger].
  PipelineCompactionStrategy(
    Iterable<CompactionStrategy> strategies, [
    CompactionTrigger? trigger,
  ]) : strategies = List<CompactionStrategy>.of(strategies),
       super(trigger ?? ((_) => true));

  /// Gets the ordered list of strategies in this pipeline.
  final List<CompactionStrategy> strategies;

  @override
  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  ) async {
    var anyCompacted = false;
    for (final strategy in strategies) {
      final compacted = await strategy.compact(
        index,
        logger: logger,
        cancellationToken: cancellationToken,
      );
      if (compacted) {
        anyCompacted = true;
      }
    }
    return anyCompacted;
  }
}
