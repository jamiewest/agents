import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';

/// Provides extension methods for [CompactionStrategy].
extension ChatStrategyExtensions on CompactionStrategy {
  /// Returns an [ChatReducer] that applies this [CompactionStrategy] to reduce
/// a list of messages.
///
/// Remarks: This allows any [CompactionStrategy] to be used wherever an
/// [ChatReducer] is expected, bridging the compaction pipeline into systems
/// bound to the `Microsoft.Extensions.AI` [ChatReducer] contract.
///
/// Returns: An [ChatReducer] that, on each call to [ReduceAsync], builds a
/// [CompactionMessageIndex] from the supplied messages and applies the
/// strategy's compaction logic, returning the resulting included messages.
///
/// [strategy] The compaction strategy to wrap as an [ChatReducer].
ChatReducer asChatReducer() {
return compactionStrategyChatReducer(strategy);
 }
 }
/// An [ChatReducer] adapter that delegates to a [CompactionStrategy].
class CompactionStrategyChatReducer extends ChatReducer {
  CompactionStrategyChatReducer(CompactionStrategy strategy) : _strategy = strategy {
  }

  final CompactionStrategy _strategy;

  Future<Iterable<ChatMessage>> reduce(
    Iterable<ChatMessage> messages,
    {CancellationToken? cancellationToken, }
  ) async {
    var index = CompactionMessageIndex.create([...messages]);
    await this._strategy.compactAsync(
      index,
      cancellationToken: cancellationToken,
    ) ;
    return index.getIncludedMessages();
  }
}
